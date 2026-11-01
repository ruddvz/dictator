import AVFoundation
import Observation
import Speech

/// On-device dictation. Recognition stays off when macOS cannot run it locally.
@MainActor @Observable
final class MicTranscriber {
    private(set) var isRunning = false
    private(set) var text = ""
    private(set) var isOnDevice = false
    private(set) var error: String?

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private let box = RequestBox()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sinkID: UUID?
    @ObservationIgnored private weak var sink: AudioSink?
    @ObservationIgnored private var finalized = ""
    @ObservationIgnored private var generation = 0

    func start(sink: AudioSink, localeIdentifier: String = "en-US", contextualStrings: [String] = []) async -> Bool {
        guard !isRunning else { return true }
        error = nil

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            error = "Speech recognition not authorized."
            return false
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        self.recognizer = recognizer
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device speech recognition is unavailable for \(localeIdentifier) on this Mac. No audio was sent for remote recognition."
            return false
        }

        self.sink = sink
        sinkID = sink.add { [box] buffer, _ in box.append(buffer) }
        isRunning = true
        self.contextualStrings = Array(contextualStrings.prefix(100))
        startTask()
        return true
    }

    func stop() {
        isRunning = false
        generation += 1
        if let sinkID { sink?.remove(sinkID) }
        sinkID = nil
        box.set(nil)
        task?.cancel()
        task = nil
    }

    func clear() {
        finalized = ""
        text = ""
    }

    func replaceText(_ value: String) {
        guard !isRunning else { return }
        finalized = value
        text = value
    }

    private func startTask() {
        guard isRunning, let recognizer else { return }
        generation += 1

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        isOnDevice = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings
        box.set(request)

        task?.cancel()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(owner: self, generation: generation))
    }

    @ObservationIgnored private var contextualStrings: [String] = []

    private func handle(generation: Int, partial: String?, isFinal: Bool, failure: String?) {
        guard generation == self.generation, isRunning else { return }
        if let partial {
            text = finalized + partial
            error = nil
        }
        if isFinal || failure != nil {
            if let partial, !partial.isEmpty { finalized += partial + " " }
            text = finalized
            if let failure { error = "Speech recognition issue: \(failure)" }
            // Recognition tasks end on silence/timeout; keep listening with a fresh one.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(failure != nil ? 500 : 50))
                self?.startTask()
            }
        }
    }

    nonisolated private static func resultHandler(owner: MicTranscriber, generation: Int)
        -> (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { [weak owner] result, error in
            let partial = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                owner?.handle(generation: generation, partial: partial, isFinal: isFinal, failure: failure)
            }
        }
    }
}

/// The current recognition request, appended to from the audio thread.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            self.request?.endAudio()
            self.request = request
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }
}
