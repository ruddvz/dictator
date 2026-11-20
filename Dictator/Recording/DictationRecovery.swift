import AVFoundation
import Foundation

/// What went wrong with the last dictation, and which recovery the pill can offer.
struct DictationNotice: Equatable {
    enum Kind: Equatable {
        /// The microphone never started, so there is no audio to retry.
        case microphone
        /// Speech recognition failed or returned an error with no text.
        case recognition
        /// Parakeet returned text from a weak or uncertain signal; keep it for review, never type it automatically.
        case review
        /// Recognition finished but heard nothing.
        case nothingHeard
        /// The microphone ran but stayed silent the whole time: muted, wrong input, or blocked.
        case silentMicrophone
        /// The person cancelled; the audio is kept briefly so Undo can transcribe it anyway.
        case cancelled
        /// The transcript is ready but could not be typed into the original field.
        case insertion
        /// "Paste again" was refused because the original app or field is not focused.
        case focusLost
        /// macOS hasn't granted the microphone or Speech Recognition, so nothing can start.
        case permission(Privacy)
    }

    /// The Privacy & Security pane that holds the missing permission.
    enum Privacy: Equatable {
        case microphone
        case speechRecognition
        case accessibility

        var settingsURL: URL? {
            switch self {
            case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            case .speechRecognition: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }
    }

    let kind: Kind
    /// A few words for the pill.
    let message: String
    /// The full reason, for the tooltip and VoiceOver.
    let detail: String
    let canRetry: Bool
    let canPasteAgain: Bool

    /// Mic problems offer Sound settings and a microphone picker instead of a retry.
    var offersMicrophoneHelp: Bool { kind == .microphone || kind == .silentMicrophone }
    /// Not a failure: shown in neutral ink instead of the danger colour.
    var isNeutral: Bool { kind == .cancelled || kind == .review }
    var isReview: Bool { kind == .review }
    /// The settings pane to open when macOS is blocking dictation.
    var missingPermission: Privacy? {
        if case .permission(let privacy) = kind { privacy } else { nil }
    }
}

enum DictationRecovery {
    /// Decides whether a finished dictation needs a notice. Text always wins over a stale
    /// recognition error, because Speech reports transient errors between its tasks.
    ///
    /// `heardSound` is false when the microphone level never rose above `silenceLevel`, so an
    /// empty result is blamed on the input rather than on the speaker.
    static func notice(audioError: String?, transcriberError: String?, transcript: String,
                       hasRetainedAudio: Bool, heardSound: Bool = true,
                       microphoneName: String? = nil) -> DictationNotice? {
        if let audioError, !audioError.isEmpty {
            return DictationNotice(kind: .microphone, message: "Microphone didn’t start", detail: audioError,
                                   canRetry: false, canPasteAgain: false)
        }
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let transcriberError, !transcriberError.isEmpty {
            return DictationNotice(kind: .recognition, message: "Couldn’t transcribe", detail: transcriberError,
                                   canRetry: hasRetainedAudio, canPasteAgain: false)
        }
        if !heardSound {
            let source = microphoneName.map { "“\($0)”" } ?? "The microphone"
            return DictationNotice(kind: .silentMicrophone, message: "No sound from the microphone",
                                   detail: "\(source) stayed silent. Check that it isn’t muted, or choose another microphone.",
                                   canRetry: false, canPasteAgain: false)
        }
        return DictationNotice(kind: .nothingHeard, message: "Didn’t catch that",
                               detail: "No words were recognized. Try again.",
                               canRetry: hasRetainedAudio, canPasteAgain: false)
    }

    /// Peak microphone level (0…1 over −60…0 dBFS) below which a recording counts as silent.
    /// A quiet room sits near 0.25; a muted or disconnected input reads close to 0.
    static let silenceLevel: Float = 0.1

    /// Recordings shorter than this are accidental taps, so cancelling them offers no Undo.
    static let minimumUndoSeconds: Double = 1

    /// Dictation couldn't start because macOS hasn't granted access. Says which switch to turn on.
    static func permissionNeeded(_ privacy: DictationNotice.Privacy) -> DictationNotice {
        switch privacy {
        case .microphone:
            DictationNotice(kind: .permission(.microphone), message: "Allow the microphone",
                            detail: "Turn on Dictator under Privacy & Security › Microphone, then dictate again.",
                            canRetry: false, canPasteAgain: false)
        case .speechRecognition:
            DictationNotice(kind: .permission(.speechRecognition), message: "Allow speech recognition",
                            detail: "Turn on Dictator under Privacy & Security › Speech Recognition, then dictate again. Recognition stays on this Mac.",
                            canRetry: false, canPasteAgain: false)
        case .accessibility:
            DictationNotice(kind: .permission(.accessibility), message: "Allow Accessibility",
                            detail: "Turn on Dictator under Privacy & Security › Accessibility, then dictate again to insert at your cursor.",
                            canRetry: false, canPasteAgain: false)
        }
    }

    static func cancelled() -> DictationNotice {
        DictationNotice(kind: .cancelled, message: "Cancelled",
                        detail: "Nothing was typed. Undo transcribes what you said and types it.",
                        canRetry: true, canPasteAgain: false)
    }

    static func reviewBeforeInsertion(confidence: Float?, peakLevel: Float) -> DictationNotice {
        // The numbers stay out of the message; they're in the log for diagnosis.
        _ = (confidence, peakLevel)
        return DictationNotice(kind: .review, message: "Check before typing",
                               detail: "Dictator wasn’t sure it heard you right, so nothing was typed. Review it, then choose Insert.",
                               canRetry: false, canPasteAgain: false)
    }

    static func insertionFailed(_ reason: String, canPasteAgain: Bool) -> DictationNotice {
        DictationNotice(kind: .insertion, message: "Couldn’t type it",
                        detail: reason + " The text is saved in Dictator.",
                        canRetry: false, canPasteAgain: canPasteAgain)
    }

    static func pasteUnconfirmed(_: String, canPasteAgain: Bool) -> DictationNotice {
        DictationNotice(kind: .insertion, message: "Check the text field",
                        detail: "It may already be there. Paste again only if it’s missing.",
                        canRetry: false, canPasteAgain: canPasteAgain)
    }

    static func focusLost(appName: String) -> DictationNotice {
        DictationNotice(kind: .focusLost, message: "Click back into \(appName)",
                        detail: "Click the text field in \(appName), then choose Paste Again.",
                        canRetry: false, canPasteAgain: true)
    }
}

/// Safety screen for Parakeet's nonempty results: text from near-silence or a doubtful model is
/// shown for review instead of typed. Calibrated on real use (2026-11-04): ordinary speech into
/// a MacBook mic peaked at 0.10–0.46 with confidence 0.57–1.00, and the old 0.45 peak floor held
/// back three of four good dictations. The floor is now the speech gate itself
/// (`SpeechEnvelope.gate`): below it, nothing counted as speech.
enum ParakeetAutoInsertGate {
    static let minimumPeakLevel: Float = SpeechEnvelope.gate
    static let minimumConfidence: Float = 0.35

    static func allowsAutomaticInsertion(peakLevel: Float, confidence: Float) -> Bool {
        !requiresReview(peakLevel: peakLevel, confidence: confidence)
    }

    /// Weak input remains review-only even if Parakeet fails and Apple Speech supplies the text.
    static func requiresReview(peakLevel: Float, confidence: Float?) -> Bool {
        peakLevel < minimumPeakLevel || (confidence.map { $0 < minimumConfidence } ?? false)
    }
}

/// A dictation the person cancelled, offered back in History for the rest of the session.
struct CancelledDictation: Identifiable, Equatable {
    let id = UUID()
    let cancelledAt: Date
    let duration: TimeInterval
    /// The app it was meant for, if any.
    let appName: String?

    var durationLabel: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// How a dictation was set up when it started, so a recovered recording is formatted the same way.
struct DictationRunSettings {
    var engine: DictationEngine
    var mode: DictationMode
    var languageIdentifier: String
    var snippets: String
    var correctionRules: String
    var cleansFillers: Bool
    var appliesSpokenCorrections: Bool
    var usesSmartCleanup: Bool
    var tone: DictationTone
    var contextualStrings: [String]
    var profileName: String?
    var writingStylePresetID: UUID?
    var usageCategory: UsageCategory
}

/// Whether "Paste again" may type the last dictation into its original target right now.
enum PasteAgainGate {
    enum Decision: Equatable {
        case allowed
        case unavailable(String)
        case focusLost
    }

    static func decision(text: String, hasTarget: Bool, isBusy: Bool, alreadyInserted: Bool,
                         insertionEnabled: Bool, targetIsFrontmost: Bool, targetFieldIsFocused: Bool) -> Decision {
        if isBusy { return .unavailable("Wait for the current dictation to finish.") }
        // Never type the same dictation twice without the user undoing the first one.
        if alreadyInserted { return .unavailable("This dictation was already typed once.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable("There is no dictation to paste.")
        }
        guard insertionEnabled else { return .unavailable("Turn on typing in Settings › Typing first.") }
        guard hasTarget else {
            return .unavailable("This dictation has no saved target field. Use Insert in Dictator instead.")
        }
        guard targetIsFrontmost, targetFieldIsFocused else { return .focusLost }
        return .allowed
    }
}

/// The last dictation's microphone audio, kept only in memory so a failed transcription can
/// run again. It is never written to disk and is dropped once a transcript succeeds, the
/// notice is dismissed, the dictation is cancelled, or a new one starts.
final class RetainedDictationAudio: @unchecked Sendable {
    /// Five minutes of 48 kHz mono float audio is about 58 MB; longer recordings are not kept.
    static let maximumSeconds: Double = 300

    private let lock = NSLock()
    private let copyBuffer: (AVAudioPCMBuffer) -> AVAudioPCMBuffer?
    private var buffers: [AVAudioPCMBuffer] = []
    private var seconds: Double = 0
    private var overflowed = false

    init(copyBuffer: @escaping (AVAudioPCMBuffer) -> AVAudioPCMBuffer? = RetainedDictationAudio.copy) {
        self.copyBuffer = copyBuffer
    }

    /// True when every buffer of the last recording is held and can be replayed.
    var isUsable: Bool { lock.withLock { !buffers.isEmpty && !overflowed } }
    var duration: Double { lock.withLock { seconds } }

    func append(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return }
        let added = Double(buffer.frameLength) / rate
        lock.lock()
        defer { lock.unlock() }
        guard Self.accepts(currentSeconds: seconds, adding: added, overflowed: overflowed) else {
            // A partial recording would retry into a truncated transcript, so drop all of it.
            overflowed = true
            buffers = []
            return
        }
        guard let copy = copyBuffer(buffer) else {
            // Any missing interval makes the retained recording unsafe to replay.
            overflowed = true
            buffers = []
            seconds = 0
            return
        }
        buffers.append(copy)
        seconds += added
    }

    func snapshot() -> [AVAudioPCMBuffer] {
        lock.withLock { overflowed ? [] : buffers }
    }

    func reset() {
        lock.withLock {
            buffers = []
            seconds = 0
            overflowed = false
        }
    }

    static func accepts(currentSeconds: Double, adding: Double, overflowed: Bool) -> Bool {
        !overflowed && currentSeconds + adding <= maximumSeconds
    }

    /// Tap buffers are reused by the audio engine, so keep a private copy.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in source.indices {
            let from = source[index], to = destination[index]
            guard let fromData = from.mData, let toData = to.mData,
                  from.mDataByteSize <= to.mDataByteSize else { return nil }
            memcpy(toData, fromData, Int(from.mDataByteSize))
        }
        return copy
    }
}

/// The card above the pill that shows live text, and keeps the final text up with Copy when
/// there was no text field to type into.
enum TranscriptCard {
    enum State: Equatable {
        case hidden
        case finished(hint: String?)
    }

    static let noTargetHint = "No text box selected. Copy it to paste."
    static let notTypedHint = "Couldn’t type it. Copy it instead."

    /// While you talk only the pill shows, as in Wispr Flow. Afterwards the card comes up only
    /// when there was nowhere to type, or typing failed and the text needs copying.
    static func state(isCapturing: Bool, hasTarget: Bool, transcript: String, keepsFinishedText: Bool) -> State {
        let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isCapturing, keepsFinishedText, hasText else { return .hidden }
        return .finished(hint: hasTarget ? notTypedHint : noTargetHint)
    }

    /// The end of a growing transcript, cut at a word boundary, so the card shows the last
    /// few lines instead of the first ones.
    static func tail(_ text: String, maxCharacters: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let suffix = trimmed.suffix(maxCharacters)
        let wordStart = suffix.firstIndex(where: \.isWhitespace).map { suffix.index(after: $0) }
        let words = wordStart.map { suffix[$0...] } ?? suffix
        let body = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return "…" + (body.isEmpty ? String(suffix) : body)
    }
}
