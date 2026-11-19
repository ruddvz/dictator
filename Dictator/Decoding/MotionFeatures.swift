import Foundation

/// Which motion channels feed the classifier. Toggling these is the ablation experiment:
/// does articulation show up in acceleration, rotation, or slow head attitude?
struct FeatureSet: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let acceleration = FeatureSet(rawValue: 1 << 0)
    static let rotation = FeatureSet(rawValue: 1 << 1)
    static let attitude = FeatureSet(rawValue: 1 << 2)
    static let all: FeatureSet = [.acceleration, .rotation, .attitude]
}

/// Why a capture is unlikely to be a clean mouthed word. Checked before a take is saved or decoded,
/// so head turns and stray key presses don't become templates or typed words.
enum TakeIssue: Equatable, Sendable {
    case tooShort
    case tooLong
    case headMoved

    var message: String {
        switch self {
        case .tooShort: "That take was too short. Hold the key for the whole word."
        case .tooLong: "That take was too long. Release the key right after the word."
        case .headMoved: "Your head moved during that take. Keep still and mouth only the word."
        }
    }

    /// Fits the capture HUD and a take tile.
    var shortMessage: String {
        switch self {
        case .tooShort: "Too short · hold for the whole word"
        case .tooLong: "Too long · release after the word"
        case .headMoved: "Head moved · keep still"
        }
    }

    var label: String {
        switch self {
        case .tooShort: "Too short"
        case .tooLong: "Too long"
        case .headMoved: "Head moved"
        }
    }
}

/// AirPods report the whole head, so jaw movement and head movement arrive mixed in one stream.
/// They separate by speed and size: on 37 real takes, mouthing a word tilted the head at most 1.3°
/// with slow (under 1.5 Hz) rotation under 0.08 rad/s, while takes with a nod or turn tilted it
/// 2–20° with slow rotation of 0.14–0.86 rad/s. So head movement is judged on the slow band and the
/// total tilt, and any take or capture where the head moved is refused. Filtering the slow band out of
/// the classifier's features instead was tried and lost accuracy (53 % → 28–41 %): a mouthed word moves
/// the jaw slowly too. See docs/SILENT_SPEECH_RESEARCH.md.
enum MotionFeatures {
    static let minTakeSeconds: TimeInterval = 0.3
    static let maxTakeSeconds: TimeInterval = 3
    /// Any spike this fast is a jerk of the head, whatever the band.
    static let maxTakeRotation = 0.6
    /// Below this frequency motion is the head moving; above it, articulation.
    static let headBandCutoff = 1.5
    /// Slow-band rotation above this is a nod or turn. Mouthed words stayed under 0.08 rad/s.
    static let maxHeadRotation = 0.12
    /// Total tilt from where the take began. Mouthed words stayed under 1.3°.
    static let maxHeadTilt = 2.5 * Double.pi / 180
    /// Sample rate assumed when timestamps can't give one (AirPods stream at about 50 Hz).
    static let nominalSampleRate = 50.0

    static func takeIssue(_ samples: [MotionSample]) -> TakeIssue? {
        guard let first = samples.first, let last = samples.last else { return .tooShort }
        let duration = last.t - first.t
        if duration < minTakeSeconds { return .tooShort }
        if duration > maxTakeSeconds { return .tooLong }
        return headMoved(samples) ? .headMoved : nil
    }

    /// True when the head itself moved during these samples, rather than only the jaw.
    static func headMoved(_ samples: [MotionSample]) -> Bool {
        let peak = samples.map { ($0.rx * $0.rx + $0.ry * $0.ry + $0.rz * $0.rz).squareRoot() }.max() ?? 0
        return peak > maxTakeRotation || slowRotationPeak(samples) > maxHeadRotation || tilt(samples) > maxHeadTilt
    }

    /// Largest slow-band rotation rate (rad/s).
    static func slowRotationPeak(_ samples: [MotionSample]) -> Double {
        guard samples.count > 2 else { return 0 }
        let rate = sampleRate(samples)
        let channels = [samples.map(\.rx), samples.map(\.ry), samples.map(\.rz)]
            .map { lowPassed($0, sampleRate: rate, cutoff: headBandCutoff) }
        return samples.indices.map { i in
            (channels[0][i] * channels[0][i] + channels[1][i] * channels[1][i] + channels[2][i] * channels[2][i]).squareRoot()
        }.max() ?? 0
    }

    /// Largest angle (rad) the head turned away from its orientation at the first sample.
    static func tilt(_ samples: [MotionSample]) -> Double {
        guard let first = samples.first else { return 0 }
        return samples.map { s in
            // Angle of the relative rotation first⁻¹·s, from the dot product of the two unit quaternions.
            let dot = abs(first.qw * s.qw + first.qx * s.qx + first.qy * s.qy + first.qz * s.qz)
            return 2 * acos(min(1, dot))
        }.max() ?? 0
    }

    static func sampleRate(_ samples: [MotionSample]) -> Double {
        guard let first = samples.first, let last = samples.last, last.t > first.t, samples.count > 1 else {
            return nominalSampleRate
        }
        return Double(samples.count - 1) / (last.t - first.t)
    }

    /// Zero-phase low-pass (one pole, run forward then backward), so nothing shifts in time.
    static func lowPassed(_ values: [Double], sampleRate: Double, cutoff: Double) -> [Double] {
        guard let first = values.first, sampleRate > 0 else { return values }
        let a = exp(-2 * Double.pi * cutoff / sampleRate)
        var state = first
        var forward = values.map { value -> Double in
            state = a * state + (1 - a) * value
            return state
        }
        state = forward[forward.count - 1]
        for i in forward.indices.reversed() {
            state = a * state + (1 - a) * forward[i]
            forward[i] = state
        }
        return forward
    }

    /// Activity score used for segmentation. Rotation (rad/s) and acceleration (g) live on
    /// different scales; the 5× weight puts typical jaw-motion values in the same range.
    static func energy(_ s: MotionSample) -> Double {
        let rotation = (s.rx * s.rx + s.ry * s.ry + s.rz * s.rz).squareRoot()
        let accel = (s.ax * s.ax + s.ay * s.ay + s.az * s.az).squareRoot()
        return rotation + 5 * accel
    }

    /// Drops quiet lead-in/lead-out frames so templates align on the articulation itself.
    /// Uses a threshold relative to the segment so it behaves the same for training and decoding.
    static func trim(_ samples: [MotionSample], padding: Int = 2) -> [MotionSample] {
        guard samples.count > 6 else { return samples }
        let energies = samples.map(energy)
        let sorted = energies.sorted()
        let floor = sorted[sorted.count / 5]
        let peak = sorted[sorted.count - 1]
        guard peak > floor * 1.5 else { return samples }
        let threshold = floor + 0.15 * (peak - floor)
        guard let first = energies.firstIndex(where: { $0 > threshold }),
              let last = energies.lastIndex(where: { $0 > threshold }) else { return samples }
        let lo = max(0, first - padding)
        let hi = min(samples.count - 1, last + padding)
        guard hi - lo + 1 >= 5 else { return samples }
        return Array(samples[lo...hi])
    }

    /// Centred moving-average width. Three samples (60 ms at 50 Hz) raised leave-one-out accuracy on real
    /// silent takes from 38 % to 43–49 % (chance 33 %) and the permutation p from 0.02 to 0.003; see
    /// docs/SILENT_SPEECH_RESEARCH.md.
    static let defaultSmoothing = 3

    /// Per-frame feature vectors: slow motion below `headCutoff` removed (off by default; kept for the
    /// offline eval), lightly smoothed,
    /// and mean-centered per channel (removes posture/heading bias).
    static func frames(_ samples: [MotionSample], set: FeatureSet, smoothing: Int = defaultSmoothing,
                       headCutoff: Double? = nil) -> [[Double]] {
        guard let origin = samples.first else { return [] }
        var frames = samples.map { s -> [Double] in
            var v: [Double] = []
            if set.contains(.acceleration) { v += [s.ax, s.ay, s.az] }
            if set.contains(.rotation) { v += [s.rx, s.ry, s.rz] }
            if set.contains(.attitude) {
                v += [wrapped(s.pitch - origin.pitch), wrapped(s.roll - origin.roll), wrapped(s.yaw - origin.yaw)]
            }
            return v
        }
        guard let dims = frames.first?.count, dims > 0 else { return frames }
        if let headCutoff, frames.count > 2 {
            let rate = sampleRate(samples)
            for d in 0..<dims {
                let slow = lowPassed(frames.map { $0[d] }, sampleRate: rate, cutoff: headCutoff)
                for i in frames.indices { frames[i][d] -= slow[i] }
            }
        }
        frames = smoothed(frames, window: smoothing)
        for d in 0..<dims {
            let mean = frames.reduce(0) { $0 + $1[d] } / Double(frames.count)
            for i in frames.indices { frames[i][d] -= mean }
        }
        return frames
    }

    /// Centred moving average per channel; the ends repeat the edge frame so length is unchanged.
    static func smoothed(_ frames: [[Double]], window: Int) -> [[Double]] {
        guard window > 1, frames.count > 1 else { return frames }
        let before = window / 2, after = window - 1 - before
        return frames.indices.map { i in
            var sum = [Double](repeating: 0, count: frames[i].count)
            for k in (i - before)...(i + after) {
                let frame = frames[min(max(k, 0), frames.count - 1)]
                for d in sum.indices { sum[d] += frame[d] }
            }
            return sum.map { $0 / Double(window) }
        }
    }

    /// Per-channel standard deviation across a corpus, so no channel dominates the distance.
    static func channelScales(_ sequences: [[[Double]]]) -> [Double] {
        guard let dims = sequences.first?.first?.count else { return [] }
        var sum = [Double](repeating: 0, count: dims)
        var sumSq = [Double](repeating: 0, count: dims)
        var n = 0.0
        for sequence in sequences {
            for frame in sequence {
                for d in 0..<dims {
                    sum[d] += frame[d]
                    sumSq[d] += frame[d] * frame[d]
                }
                n += 1
            }
        }
        guard n > 1 else { return [Double](repeating: 1, count: dims) }
        return (0..<dims).map { d in
            let mean = sum[d] / n
            return max((sumSq[d] / n - mean * mean).squareRoot(), 1e-6)
        }
    }

    static func scaled(_ frames: [[Double]], by scales: [Double]) -> [[Double]] {
        frames.map { frame in zip(frame, scales).map { $0 / $1 } }
    }

    private static func wrapped(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }
}
