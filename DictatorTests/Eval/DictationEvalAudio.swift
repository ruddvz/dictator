import AVFoundation
import Foundation
import DictatorParakeet
import Speech
@testable import Dictator

/// Modes scored for every clip. Automatic resolves to one of these from the frontmost app, so it is not scored separately.
let evalModes: [DictationMode] = [.natural, .message, .email, .code]

struct EvalTranscript {
    var text: String
    var error: String?
}

@MainActor
protocol DictationEvalEngine {
    var name: String { get }
    /// Returns nil when the engine can run, or the reason it is skipped. Never downloads or prompts indefinitely.
    func unavailableReason() async -> String?
    func transcribe(_ url: URL) async -> EvalTranscript
}

/// Apple on-device Speech through the app's own `LocalFileTranscriber` (the Transcribe Files path).
@MainActor
final class AppleSpeechEvalEngine: DictationEvalEngine {
    let localeIdentifier: String
    private let transcriber = LocalFileTranscriber()
    private let clipTimeout: Duration

    init(localeIdentifier: String, clipTimeout: Duration = .seconds(60)) {
        self.localeIdentifier = localeIdentifier
        self.clipTimeout = clipTimeout
    }

    var name: String { "apple-speech (\(localeIdentifier), on-device)" }

    func unavailableReason() async -> String? {
        let status = await Self.authorization(timeout: 30)
        guard status == .authorized else {
            return "Speech recognition is not authorized for the test host (status \(status.rawValue)). "
                + "Run the harness once with the user present to accept the Dictator Speech prompt."
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.supportsOnDeviceRecognition else {
            return "On-device recognition is unavailable for \(localeIdentifier)."
        }
        return nil
    }

    func transcribe(_ url: URL) async -> EvalTranscript {
        let watchdog = Task { [transcriber, clipTimeout] in
            try? await Task.sleep(for: clipTimeout)
            if !Task.isCancelled { transcriber.cancel() }
        }
        await transcriber.transcribe(file: url, localeIdentifier: localeIdentifier)
        watchdog.cancel()
        let timedOut = transcriber.status == "Transcription cancelled."
        let text = transcriber.text
        let error = timedOut ? "Timed out after \(clipTimeout)." : transcriber.error
        transcriber.clear()
        return EvalTranscript(text: text, error: error)
    }

    /// Requests authorization without hanging when a permission prompt is never answered.
    private static func authorization(timeout seconds: Double) async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>?
            init(_ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) {
                self.continuation = continuation
            }
            func resume(_ status: SFSpeechRecognizerAuthorizationStatus) {
                lock.lock()
                let pending = continuation
                continuation = nil
                lock.unlock()
                pending?.resume(returning: status)
            }
        }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            SFSpeechRecognizer.requestAuthorization { once.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(.notDetermined) }
        }
    }
}

/// A WhisperKit model the user already downloaded in Dictator, run through `WhisperKitFileTranscriber`.
/// The harness never downloads models and restores the user's model selection afterwards.
@MainActor
final class WhisperKitEvalEngine: DictationEvalEngine {
    let variant: WhisperModelVariant
    let languageIdentifier: String
    private let transcriber = WhisperKitFileTranscriber()
    private let clipTimeout: Duration

    init(variant: WhisperModelVariant, languageIdentifier: String, clipTimeout: Duration = .seconds(180)) {
        self.variant = variant
        self.languageIdentifier = languageIdentifier
        self.clipTimeout = clipTimeout
    }

    var name: String { "whisperkit-\(variant.rawValue)" }

    func unavailableReason() async -> String? {
        Self.isInstalled(variant, in: transcriber)
            ? nil
            : "Model \(variant.rawValue) is not downloaded in Dictator; the harness does not download models."
    }

    func transcribe(_ url: URL) async -> EvalTranscript {
        let previous = transcriber.selectedVariant
        transcriber.selectedVariant = variant
        defer { transcriber.selectedVariant = previous }
        transcriber.transcribe(file: url, languageIdentifier: languageIdentifier)
        let deadline = ContinuousClock.now + clipTimeout
        while transcriber.isTranscribing {
            if ContinuousClock.now > deadline { transcriber.cancelTranscription() }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let result = EvalTranscript(text: transcriber.text, error: transcriber.error ??
            (transcriber.status == "Transcription cancelled." ? "Timed out after \(clipTimeout)." : nil))
        transcriber.clear()
        return result
    }

    /// Installed variants, read from Dictator's own model records.
    static func installedVariants() -> [WhisperModelVariant] {
        let probe = WhisperKitFileTranscriber()
        return WhisperModelVariant.allCases.filter { isInstalled($0, in: probe) }
    }

    private static func isInstalled(_ variant: WhisperModelVariant, in transcriber: WhisperKitFileTranscriber) -> Bool {
        guard let path = transcriber.downloadedModels[variant.rawValue] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Parakeet through the app's own `ParakeetDictationEngine` (the dictation path), using a model
/// already downloaded in Dictator's real Application Support folder. Read-only; never downloads.
@MainActor
final class ParakeetEvalEngine: DictationEvalEngine {
    let model: ParakeetModel
    private let engine: ParakeetDictationEngine

    init(model: ParakeetModel) {
        self.model = model
        engine = ParakeetDictationEngine(modelRoot: Self.installedRoot, model: model)
    }

    /// The tests' `AppDataDirectory` is a temporary folder, so point at the user's models directly.
    static var installedRoot: URL {
        URL.applicationSupportDirectory.appending(path: AppDataDirectory.folderName, directoryHint: .isDirectory)
            .appending(path: "ParakeetModels", directoryHint: .isDirectory)
    }

    static func installedModels() -> [ParakeetModel] {
        ParakeetModel.allCases.filter { $0.isDownloaded(in: installedRoot) }
    }

    var name: String {
        switch model {
        case .englishUltra: "parakeet-ultra (on-device)"
        case .englishV2: "parakeet-v2 (on-device)"
        case .multilingualV3: "parakeet-v3 (on-device)"
        }
    }

    func unavailableReason() async -> String? {
        guard engine.isDownloaded else {
            return "\(model.rawValue) is not downloaded in Dictator; the harness does not download models."
        }
        // Load before timing, as the app does at launch.
        return await engine.warmUp().value ? nil : "\(model.rawValue) did not load."
    }

    func transcribe(_ url: URL) async -> EvalTranscript {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                return EvalTranscript(text: "", error: "Could not read \(url.lastPathComponent).")
            }
            try file.read(into: buffer)
            return EvalTranscript(text: try await engine.transcribe([buffer]).text, error: nil)
        } catch {
            return EvalTranscript(text: "", error: error.localizedDescription)
        }
    }
}

// MARK: - Audio results

struct ModeResult: Codable {
    var mode: String
    var output: String
    /// The processor applied to the reference words; the ideal output for this clip and mode.
    var oracle: String
    var formattedErrors: EditCounts
    var checksTotal: Int
    var failedChecks: [String]
}

struct ClipResult: Codable {
    var id: String
    var split: EvalSplit
    /// `recorded` (consented clip in Fixtures) or `synthetic` (local text-to-speech bootstrap).
    var source: String
    var audioSeconds: Double
    var transcribeSeconds: Double
    var raw: String
    var error: String?
    var wordErrors: EditCounts
    var modes: [ModeResult]
}

struct EngineResult: Codable {
    var engine: String
    var skippedReason: String?
    var clips: [ClipResult]
}

enum AudioEval {
    private static let audioExtensions = ["wav", "m4a", "caf", "aiff", "mp3"]

    static func audioFile(for clip: AudioEvalClip, split: EvalSplit) -> (url: URL, source: String)? {
        for (directory, source) in [(EvalPaths.recordedAudio(split), "recorded"), (EvalPaths.syntheticAudio(split), "synthetic")] {
            for ext in audioExtensions {
                let url = directory.appending(path: "\(clip.id).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return (url, source) }
            }
        }
        return nil
    }

    static func modeResults(raw: String, clip: AudioEvalClip) -> [ModeResult] {
        evalModes.map { mode in
            let process = { (text: String) in
                DictationTranscriptProcessor.process(text, mode: mode, snippets: clip.snippets ?? "",
                                                     cleanupFillers: clip.cleanupFillers ?? false)
            }
            let output = process(raw)
            let oracle = process(clip.reference)
            let check = clip.checks?[mode.rawValue]
            let total = (check?.contains?.count ?? 0) + (check?.absent?.count ?? 0)
            return ModeResult(mode: mode.rawValue, output: output, oracle: oracle,
                              formattedErrors: EvalScoring.formattedErrors(expected: oracle, actual: output),
                              checksTotal: total,
                              failedChecks: check.map { EvalScoring.failedChecks($0, output: output) } ?? [])
        }
    }

    @MainActor
    static func run(_ engine: DictationEvalEngine, splits: [EvalSplit]) async throws -> EngineResult {
        if let reason = await engine.unavailableReason() {
            return EngineResult(engine: engine.name, skippedReason: reason, clips: [])
        }
        var clips: [ClipResult] = []
        for split in splits {
            for clip in try EvalFixtures.audioClips(split) {
                guard let audio = audioFile(for: clip, split: split) else {
                    clips.append(ClipResult(id: clip.id, split: split, source: "missing", audioSeconds: 0,
                                            transcribeSeconds: 0, raw: "", error: "No audio file for this clip.",
                                            wordErrors: EvalScoring.wordErrors(reference: clip.reference, hypothesis: ""),
                                            modes: []))
                    continue
                }
                let started = ContinuousClock.now
                let transcript = await engine.transcribe(audio.url)
                let elapsed = started.duration(to: .now)
                clips.append(ClipResult(
                    id: clip.id, split: split, source: audio.source,
                    audioSeconds: duration(of: audio.url),
                    transcribeSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
                    raw: transcript.text, error: transcript.error,
                    wordErrors: EvalScoring.wordErrors(reference: clip.reference, hypothesis: transcript.text),
                    modes: modeResults(raw: transcript.text, clip: clip)))
            }
        }
        return EngineResult(engine: engine.name, skippedReason: nil, clips: clips)
    }

    private static func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
