import AVFoundation
import Observation
import Speech

/// On-device dictation. Recognition stays off when macOS cannot run it locally.
@MainActor @Observable
final class MicTranscriber {
    private(set) var isRunning = false
    private(set) var isFinalizing = false
    private(set) var text = ""
    private(set) var isOnDevice = false
    private(set) var error: String?

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private let box = RequestBox()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sinkID: UUID?
    @ObservationIgnored private weak var sink: AudioSink?
    @ObservationIgnored private var stitcher = TranscriptStitcher()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var finalizationContinuation: CheckedContinuation<String, Never>?
    @ObservationIgnored private var finalizationTimeoutTask: Task<Void, Never>?

    func start(sink: AudioSink, localeIdentifier: String = "en-US", contextualStrings: [String] = []) async -> Bool {
        guard !isRunning, !isFinalizing else { return false }
        error = nil
        guard await prepareRecognizer(localeIdentifier: localeIdentifier) else { return false }

        self.sink = sink
        sinkID = sink.add { [box] buffer, _ in box.append(buffer) }
        isRunning = true
        self.contextualStrings = Array(contextualStrings.prefix(DictationContextHints.maximumCount))
        startTask()
        return true
    }

    /// Runs recognition again over audio that was already recorded, for a failed dictation.
    /// Finishes like a live session: call `waitForFinalization()` for the text.
    func transcribe(recorded buffers: [AVAudioPCMBuffer], localeIdentifier: String = "en-US",
                    contextualStrings: [String] = []) async -> Bool {
        guard !isRunning, !isFinalizing, !buffers.isEmpty else { return false }
        error = nil
        guard await prepareRecognizer(localeIdentifier: localeIdentifier), let recognizer,
              !isRunning, !isFinalizing else { return false }
        clear()
        generation += 1
        isFinalizing = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Partials let the stitcher keep every phrase when Speech restarts after a pause.
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = Array(contextualStrings.prefix(DictationContextHints.maximumCount))
        for buffer in buffers { request.append(buffer) }
        request.endAudio()
        isOnDevice = true
        task?.cancel()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(owner: self, generation: generation))

        let seconds = buffers.reduce(0.0) { $0 + Double($1.frameLength) / max($1.format.sampleRate, 1) }
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10 + seconds))
            self?.completeFinalization()
        }
        return true
    }

    private func prepareRecognizer(localeIdentifier: String) async -> Bool {
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
        return true
    }

    func stop() {
        isRunning = false
        isFinalizing = false
        generation += 1
        if let sinkID { sink?.remove(sinkID) }
        sinkID = nil
        box.set(nil)
        task?.cancel()
        task = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        finalizationContinuation?.resume(returning: text)
        finalizationContinuation = nil
    }

    /// Stops accepting microphone buffers, then waits briefly for Speech's final partial.
    func beginFinalization() {
        guard isRunning else { return }
        isRunning = false
        isFinalizing = true
        if let sinkID { sink?.remove(sinkID) }
        sinkID = nil
        box.set(nil)
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.completeFinalization()
        }
    }

    func waitForFinalization() async -> String {
        guard isFinalizing else { return text }
        return await withCheckedContinuation { continuation in
            finalizationContinuation = continuation
            if !isFinalizing {
                finalizationContinuation = nil
                continuation.resume(returning: text)
            }
        }
    }

    func clear() {
        stitcher = TranscriptStitcher()
        text = ""
    }

    func replaceText(_ value: String) {
        guard !isRunning else { return }
        stitcher = TranscriptStitcher(text: value)
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

    private func handle(generation: Int, result: SpeechResult) {
        guard generation == self.generation, isRunning || isFinalizing else { return }
        if let partial = result.text {
            stitcher.update(partial: partial, start: result.start, end: result.end)
            text = stitcher.text
            error = nil
        }
        guard result.isFinal || result.failure != nil else { return }
        // The task is over, by a final result, silence, or an error. Keep every word heard so far.
        stitcher.commit()
        text = stitcher.text
        if let failure = result.failure, !result.isBenignEnd {
            error = "Speech recognition issue: \(failure)"
        }
        if isFinalizing {
            completeFinalization()
            return
        }
        // Recognition tasks end on silence/timeout; keep listening with a fresh one.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(result.failure != nil && !result.isBenignEnd ? 500 : 50))
            self?.startTask()
        }
    }

    private func completeFinalization() {
        guard isFinalizing else { return }
        isFinalizing = false
        generation += 1
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        task?.cancel()
        task = nil
        box.set(nil)
        finalizationContinuation?.resume(returning: text)
        finalizationContinuation = nil
    }

    /// One Speech callback, copied off the recognition thread.
    struct SpeechResult: Sendable {
        var text: String?
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var isFinal = false
        var failure: String?
        /// Silence or a cancelled task: normal between phrases, not worth showing as an error.
        var isBenignEnd = false

        /// kAFAssistantErrorDomain 1110 "No speech detected", 216/301 cancelled, 203 retry.
        static func isBenign(domain: String, code: Int) -> Bool {
            domain == "kAFAssistantErrorDomain" && [203, 216, 301, 1107, 1110].contains(code)
        }
    }

    nonisolated private static func resultHandler(owner: MicTranscriber, generation: Int)
        -> (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { [weak owner] result, error in
            let segments = result?.bestTranscription.segments ?? []
            var speech = SpeechResult(text: result?.bestTranscription.formattedString,
                                      isFinal: result?.isFinal ?? false,
                                      failure: error?.localizedDescription)
            if let first = segments.first, let last = segments.last {
                speech.start = first.timestamp
                speech.end = last.timestamp + last.duration
            }
            if let error = error as NSError? {
                speech.isBenignEnd = SpeechResult.isBenign(domain: error.domain, code: error.code)
            }
            Task { @MainActor in
                owner?.handle(generation: generation, result: speech)
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
