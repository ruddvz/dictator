import Foundation
import Observation

/// Cuts the continuous motion stream into word-sized segments, either while the configured shortcut is held
/// or automatically when motion energy rises above a calibrated noise floor.
@MainActor @Observable
final class CaptureController {
    enum Mode: String, CaseIterable, Identifiable {
        case hold = "Hold key"
        case auto = "Auto-detect"
        var id: String { rawValue }
    }

    static let calibrationSeconds: TimeInterval = 2
    static let prerollSeconds: TimeInterval = 0.3
    static let hangoverSeconds: TimeInterval = 0.35
    static let maxAutoSeconds: TimeInterval = 3
    static let maxHoldSeconds: TimeInterval = 6

    var autoEnabled = false {
        didSet { if !autoEnabled, isCapturing, !isManual { finish() } }
    }
    var triggerRatio: Double = 3

    private(set) var isCapturing = false
    private(set) var isCalibrating = false
    /// The head itself is moving (a nod, turn or tilt), not just the jaw. Train and Silent Use warn
    /// while it's true; auto-capture never starts on it and drops a capture it spoils.
    private(set) var headIsMoving = false
    private(set) var energy: Double = 0
    private(set) var noiseFloor: Double?

    var threshold: Double? { noiseFloor.map { $0 * triggerRatio } }

    var onSegment: (([MotionSample]) -> Void)?
    /// A held capture ended before it held a word, so the user can be told rather than left guessing.
    var onTooShort: (() -> Void)?

    @ObservationIgnored private var isManual = false
    @ObservationIgnored private var buffer: [MotionSample] = []
    @ObservationIgnored private var preroll: [MotionSample] = []
    @ObservationIgnored private var calibration: [Double] = []
    @ObservationIgnored private var calibrationEnd: TimeInterval?
    @ObservationIgnored private var quietSince: TimeInterval?
    /// Slow-band rotation, causal: what the head is doing as opposed to the jaw.
    @ObservationIgnored private var slowRotation: (Double, Double, Double) = (0, 0, 0)
    @ObservationIgnored private var headStillSince: TimeInterval?
    @ObservationIgnored private var headMovedDuringCapture = false
    /// After the head settles, auto-capture waits this long before it may trigger again.
    static let headSettleSeconds: TimeInterval = 0.4

    func begin() {
        guard !isCapturing else { return }
        isManual = true
        isCapturing = true
        headMovedDuringCapture = false
        buffer = preroll
    }

    func end() {
        guard isCapturing, isManual else { return }
        finish()
    }

    /// Drops a capture without emitting it, for an aborted hold, lost motion stream, or page change.
    func cancel() {
        guard isCapturing || isCalibrating else { return }
        discard()
        isCalibrating = false
        calibration = []
        calibrationEnd = nil
    }

    func calibrate() {
        calibration = []
        calibrationEnd = nil
        isCalibrating = true
    }

    func ingest(_ sample: MotionSample) {
        let e = MotionFeatures.energy(sample)
        energy = energy * 0.6 + e * 0.4
        trackHead(sample)

        if isCalibrating {
            let end = calibrationEnd ?? sample.t + Self.calibrationSeconds
            calibrationEnd = end
            calibration.append(energy)
            if sample.t >= end {
                let sorted = calibration.sorted()
                noiseFloor = max(sorted[sorted.count / 2], 1e-4)
                isCalibrating = false
            }
        }

        preroll.append(sample)
        if let keepFrom = preroll.firstIndex(where: { $0.t >= sample.t - Self.prerollSeconds }), keepFrom > 0 {
            preroll.removeFirst(keepFrom)
        }

        if isCapturing {
            buffer.append(sample)
            let duration = sample.t - (buffer.first?.t ?? sample.t)
            if let first = buffer.first, MotionFeatures.tilt([first, sample]) > MotionFeatures.maxHeadTilt {
                setHeadMoving(true, at: sample.t)
            }
            if headIsMoving { headMovedDuringCapture = true }
            if !isManual, headMovedDuringCapture {
                discard() // a nod is not a word; don't decode it or report it
                return
            }
            if isManual {
                if duration > Self.maxHoldSeconds { finish() }
            } else if let threshold {
                if energy < threshold * 0.7 {
                    let since = quietSince ?? sample.t
                    quietSince = since
                    if sample.t - since > Self.hangoverSeconds { finish() }
                } else {
                    quietSince = nil
                }
                if duration > Self.maxAutoSeconds { finish() }
            }
        } else if autoEnabled, !isCalibrating, let threshold, energy > threshold, headHasSettled(at: sample.t) {
            isManual = false
            isCapturing = true
            quietSince = nil
            headMovedDuringCapture = false
            buffer = preroll
        }
    }

    /// Follows the slow band of rotation, with hysteresis so the flag doesn't flicker.
    private func trackHead(_ sample: MotionSample) {
        let a = exp(-2 * Double.pi * MotionFeatures.headBandCutoff / MotionFeatures.nominalSampleRate)
        slowRotation = (a * slowRotation.0 + (1 - a) * sample.rx,
                        a * slowRotation.1 + (1 - a) * sample.ry,
                        a * slowRotation.2 + (1 - a) * sample.rz)
        let slow = (slowRotation.0 * slowRotation.0 + slowRotation.1 * slowRotation.1
                    + slowRotation.2 * slowRotation.2).squareRoot()
        let fast = (sample.rx * sample.rx + sample.ry * sample.ry + sample.rz * sample.rz).squareRoot()
        if slow > MotionFeatures.maxHeadRotation || fast > MotionFeatures.maxTakeRotation {
            setHeadMoving(true, at: sample.t)
        } else if headIsMoving, slow < MotionFeatures.maxHeadRotation * 0.6, !tiltedDuringCapture(sample) {
            setHeadMoving(false, at: sample.t)
        }
    }

    private func tiltedDuringCapture(_ sample: MotionSample) -> Bool {
        guard isCapturing, let first = buffer.first else { return false }
        return MotionFeatures.tilt([first, sample]) > MotionFeatures.maxHeadTilt
    }

    private func setHeadMoving(_ moving: Bool, at time: TimeInterval) {
        if !moving { headStillSince = time }
        if headIsMoving != moving { headIsMoving = moving }
    }

    private func headHasSettled(at time: TimeInterval) -> Bool {
        guard !headIsMoving else { return false }
        guard let since = headStillSince else { return true }
        return time - since >= Self.headSettleSeconds
    }

    private func discard() {
        buffer = []
        isCapturing = false
        isManual = false
        quietSince = nil
        headMovedDuringCapture = false
    }

    private func finish() {
        let segment = buffer
        let wasManual = isManual
        buffer = []
        isCapturing = false
        isManual = false
        quietSince = nil
        guard segment.count >= 4, let first = segment.first, let last = segment.last, last.t - first.t >= 0.15 else {
            if wasManual { onTooShort?() }
            return
        }
        onSegment?(segment)
    }
}
