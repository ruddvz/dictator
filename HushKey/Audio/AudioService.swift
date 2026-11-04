import AVFoundation
import CoreAudio
import Foundation
import Observation
import os

/// Fans microphone buffers out to consumers (speech recognizer, session recorder) on the
/// audio render thread. Consumers must be cheap and thread-safe.
final class AudioSink: @unchecked Sendable {
    typealias Consumer = (AVAudioPCMBuffer, AVAudioTime) -> Void

    private let lock = NSLock()
    private var consumers: [UUID: Consumer] = [:]
    private var onLevel: ((Float) -> Void)?

    func add(_ consumer: @escaping Consumer) -> UUID {
        let id = UUID()
        lock.withLock { consumers[id] = consumer }
        return id
    }

    func remove(_ id: UUID) {
        lock.withLock { _ = consumers.removeValue(forKey: id) }
    }

    func setLevelHandler(_ handler: ((Float) -> Void)?) {
        lock.withLock { onLevel = handler }
    }

    func dispatch(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        let (current, levelHandler) = lock.withLock { (Array(consumers.values), onLevel) }
        for consumer in current { consumer(buffer, time) }
        levelHandler?(Self.normalizedLevel(buffer))
    }

    /// RMS of channel 0 mapped from -60…0 dBFS onto 0…1.
    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 60) / 60))
    }
}

/// Keeps render-thread meter callbacks from creating a backlog of MainActor tasks.
/// The audio tap still accounts for every sample in the peak; the UI receives the latest
/// level at most 30 times per second and never replays stale meter updates.
final class AudioLevelMailbox: @unchecked Sendable {
    struct Update {
        let level: Float
        let peak: Float
    }

    static let minimumInterval: TimeInterval = 1.0 / 30.0

    private let lock = NSLock()
    private var latest: Float = 0
    private var peak: Float = 0
    private var taskPending = false
    private var lastScheduledAt = -Double.infinity

    /// Returns true when the caller should enqueue one MainActor delivery.
    func offer(_ level: Float, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.withLock {
            latest = level
            peak = max(peak, level)
            guard !taskPending, time - lastScheduledAt >= Self.minimumInterval else { return false }
            taskPending = true
            lastScheduledAt = time
            return true
        }
    }

    /// Takes all samples since the previous delivery, then allows one new task to queue.
    func take() -> Update {
        lock.withLock {
            let update = Update(level: latest, peak: peak)
            peak = 0
            taskPending = false
            return update
        }
    }

    func reset() {
        lock.withLock {
            latest = 0
            peak = 0
            taskPending = false
            lastScheduledAt = -Double.infinity
        }
    }
}

@MainActor @Observable
final class AudioService {
    private(set) var isRunning = false
    private(set) var isStarting = false
    /// macOS is showing its microphone permission prompt.
    private(set) var isAwaitingPermission = false
    private(set) var level: Float = 0
    /// Loudest level since the last start, so an empty result can tell a silent mic from silence.
    @ObservationIgnored private(set) var peakLevel: Float = 0
    private(set) var devices: [AudioDevices.Device] = []
    private(set) var activeDeviceName: String?
    private(set) var error: String?
    /// `nil` means "system default input".
    var selectedDeviceID: AudioDeviceID? {
        didSet {
            guard oldValue != selectedDeviceID else { return }
            guard !isRunning, !isStarting else {
                selectedDeviceID = oldValue
                error = "Stop the current recording before changing microphones."
                return
            }
        }
    }

    @ObservationIgnored let sink = AudioSink()
    @ObservationIgnored private let levelMailbox = AudioLevelMailbox()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var permissionTask: Task<LocalPermissionOutcome, Never>?
    @ObservationIgnored private var permissionRequestID: UUID?
    @ObservationIgnored private var startGeneration = 0

    func refreshDevices() {
        devices = AudioDevices.inputDevices()
    }

    func start() async {
        guard !isRunning, !isStarting else { return }
        startGeneration += 1
        let generation = startGeneration
        isStarting = true
        defer {
            if generation == startGeneration { isStarting = false }
        }
        error = nil
        peakLevel = 0
        levelMailbox.reset()

        let requestID = UUID()
        permissionRequestID = requestID
        isAwaitingPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        let request = Task { await LocalPermissionAccess.microphone() }
        permissionTask = request
        let permission = await request.value
        isAwaitingPermission = false
        guard generation == startGeneration, permissionRequestID == requestID else { return }
        permissionRequestID = nil
        permissionTask = nil
        guard permission == .authorized else {
            switch permission {
            case .denied:
                error = "Microphone access is off. Enable HushKey in System Settings → Privacy & Security → Microphone, then retry."
            case .restricted:
                error = "macOS restricts microphone access for this account."
            case .timedOut:
                error = "macOS did not finish the microphone permission request. Allow HushKey in System Settings, then retry."
            case .cancelled:
                error = "Microphone permission request was cancelled."
            case .authorized:
                error = nil
            }
            return
        }

        let engineStart = ProcessInfo.processInfo.systemUptime
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let deviceID = selectedDeviceID ?? AudioDevices.defaultInputID()
        if let selectedDeviceID, let unit = input.audioUnit {
            var id = selectedDeviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                error = "Couldn't switch input device (\(status))."
                return
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "Input device has no usable format."
            return
        }

        let mailbox = levelMailbox
        sink.setLevelHandler { [weak self, mailbox] level in
            guard mailbox.offer(level) else { return }
            Task { @MainActor in
                guard let self, self.startGeneration == generation else { return }
                let update = mailbox.take()
                self.level = update.level
                self.peakLevel = max(self.peakLevel, update.peak)
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(for: sink))

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = error.localizedDescription
            return
        }

        self.engine = engine
        Logger(subsystem: "com.ruddvz.hushkey", category: "start").notice(
            "audio engine build+start \(String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - engineStart) * 1000), privacy: .public)ms")
        activeDeviceName = deviceID.flatMap(AudioDevices.name(of:))
        isRunning = true
    }

    func stop() {
        startGeneration += 1
        let finalLevel = levelMailbox.take()
        peakLevel = max(peakLevel, finalLevel.peak)
        permissionRequestID = nil
        permissionTask?.cancel()
        permissionTask = nil
        isAwaitingPermission = false
        isStarting = false
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        sink.setLevelHandler(nil)
        isRunning = false
        level = 0
        activeDeviceName = nil
    }

    // Built outside main-actor isolation: the tap runs on the audio render thread.
    nonisolated private static func tapBlock(for sink: AudioSink) -> AVAudioNodeTapBlock {
        { buffer, time in sink.dispatch(buffer, time) }
    }
}
