import Foundation
import Observation
import Speech
import AVFoundation

struct SubtitleCue: Codable, Equatable {
    var start: TimeInterval
    var duration: TimeInterval
    var text: String
}

@MainActor @Observable
final class LocalFileTranscriber {
    private(set) var isTranscribing = false
    private(set) var text = ""
    private(set) var cues: [SubtitleCue] = []
    private(set) var sourceName: String?
    private(set) var status: String?
    private(set) var error: String?

    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var authorizationTask: Task<LocalPermissionOutcome, Never>?
    @ObservationIgnored private var authorizationRequestID: UUID?
    @ObservationIgnored private var completion: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var onSessionUpdate: ((FileTranscriptionSession) -> Void)?
    @ObservationIgnored private(set) var activeSessionID = UUID()
    @ObservationIgnored private var activeLanguageIdentifier = "en-US"
    @ObservationIgnored private var sourceDuration: TimeInterval?

    func transcribe(file url: URL, localeIdentifier: String, sessionID: UUID = UUID()) async {
        guard !isTranscribing else { return }
        generation += 1
        let currentGeneration = generation
        activeSessionID = sessionID
        activeLanguageIdentifier = localeIdentifier
        isTranscribing = true
        text = ""
        cues = []
        error = nil
        sourceName = url.lastPathComponent
        sourceDuration = nil
        status = "Checking local speech support…"

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = "Waiting for macOS Speech permission…"
        }
        let authorizationRequest = Task { await LocalPermissionAccess.speechRecognition() }
        let authorizationRequestID = UUID()
        self.authorizationRequestID = authorizationRequestID
        authorizationTask = authorizationRequest
        let authorization = await authorizationRequest.value
        guard self.authorizationRequestID == authorizationRequestID else { return }
        self.authorizationRequestID = nil
        authorizationTask = nil
        guard currentGeneration == generation else { return }
        guard authorization == .authorized else {
            let message: String
            switch authorization {
            case .denied:
                message = "Allow Dictator under System Settings → Privacy & Security → Speech Recognition to transcribe files on this Mac."
            case .restricted:
                message = "macOS restricts Speech recognition for this account. Dictator did not send the file to a remote service."
            case .timedOut:
                message = "macOS did not finish the Speech permission request. Allow Dictator in System Settings, then try again."
            case .cancelled:
                message = "Speech permission request was cancelled."
            case .authorized:
                message = ""
            }
            finish(error: message)
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            finish(error: "On-device recognition for this language is unavailable. Dictator did not send the file to a remote service.")
            return
        }

        status = "Checking audio duration…"
        if let loadedDuration = try? await AVURLAsset(url: url).load(.duration), loadedDuration.seconds.isFinite {
            sourceDuration = max(0, loadedDuration.seconds)
        }
        guard currentGeneration == generation else { return }

        status = "Transcribing on this Mac…"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            completion = continuation
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
                let text = result?.bestTranscription.formattedString
                let cues = result?.bestTranscription.segments.map {
                    SubtitleCue(start: $0.timestamp, duration: $0.duration, text: $0.substring)
                }
                let isFinal = result?.isFinal ?? false
                let message = recognitionError?.localizedDescription
                Task { @MainActor in
                    self?.receive(text: text, cues: cues, isFinal: isFinal,
                                  error: message, generation: currentGeneration)
                }
            }
        }
    }

    func cancel() {
        guard isTranscribing else { return }
        generation += 1
        authorizationRequestID = nil
        authorizationTask?.cancel()
        authorizationTask = nil
        task?.cancel()
        task = nil
        isTranscribing = false
        status = "Transcription cancelled."
        persistActiveSessionIfNeeded()
        completion?.resume()
        completion = nil
    }

    func replaceText(_ value: String) {
        guard !isTranscribing else { return }
        text = value
    }

    func clear() {
        guard !isTranscribing else { return }
        text = ""
        cues = []
        sourceName = nil
        status = nil
        error = nil
        activeSessionID = UUID()
    }

    func restore(_ session: FileTranscriptionSession) {
        guard !isTranscribing else { return }
        text = session.text
        cues = session.cues
        sourceName = session.sourceName
        activeSessionID = session.id
        activeLanguageIdentifier = session.languageIdentifier
        status = "Restored from this Mac. Original audio was not copied."
        error = nil
    }

    private func receive(text value: String?, cues valueCues: [SubtitleCue]?, isFinal: Bool,
                         error message: String?, generation receivedGeneration: Int) {
        guard receivedGeneration == generation, isTranscribing else { return }
        if let value { text = value }
        if let valueCues { cues = SubtitleCueLimiter.clamp(valueCues, to: sourceDuration) }
        guard isFinal || message != nil else { return }
        task = nil
        isTranscribing = false
        if let message {
            error = text.isEmpty
                ? "Local transcription failed: \(message)"
                : "Transcription ended early. The partial transcript is kept: \(message)"
            status = nil
        } else {
            status = text.isEmpty ? "No speech was detected in this file." : "Finished locally. The source audio was not changed."
        }
        persistActiveSessionIfNeeded()
        completion?.resume()
        completion = nil
    }

    private func finish(error message: String) {
        isTranscribing = false
        status = nil
        error = message
    }

    private func persistActiveSessionIfNeeded() {
        guard let sourceName, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSessionUpdate?(FileTranscriptionSession(
            id: activeSessionID,
            sourceName: sourceName,
            engine: .apple,
            languageIdentifier: activeLanguageIdentifier,
            text: text,
            cues: cues))
    }
}

enum SubtitleFormatter {
    static func srt(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.start + cue.duration, separator: ","))\n\(cue.text)"
        }.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
    }

    static func vtt(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.start + cue.duration, separator: "."))\n\(cue.text)"
        }.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
    }

    private static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let secs = (milliseconds / 1_000) % 60
        let millis = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, millis)
    }
}

enum SubtitleCueLimiter {
    static func clamp(_ cues: [SubtitleCue], to sourceDuration: TimeInterval?) -> [SubtitleCue] {
        guard let sourceDuration, sourceDuration.isFinite else { return cues }
        let limit = floor(max(0, sourceDuration) * 1_000) / 1_000
        return cues.compactMap { cue in
            guard cue.start.isFinite, cue.duration.isFinite else { return nil }
            let start = min(max(0, cue.start), limit)
            let end = min(max(start, cue.start + cue.duration), limit)
            guard start < limit, end > start else { return nil }
            return SubtitleCue(start: start, duration: end - start, text: cue.text)
        }
    }
}
