import AVFoundation
import Foundation

/// What went wrong with the last dictation, and which recovery the pill can offer.
struct DictationNotice: Equatable {
    enum Kind: Equatable {
        /// The microphone never started, so there is no audio to retry.
        case microphone
        /// Speech recognition failed or returned an error with no text.
        case recognition
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
    var isNeutral: Bool { kind == .cancelled }
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
            return DictationNotice(kind: .microphone, message: "Mic didn't start", detail: audioError,
                                   canRetry: false, canPasteAgain: false)
        }
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let transcriberError, !transcriberError.isEmpty {
            return DictationNotice(kind: .recognition, message: "Couldn't transcribe", detail: transcriberError,
                                   canRetry: hasRetainedAudio, canPasteAgain: false)
        }
        if !heardSound {
            let source = microphoneName.map { "“\($0)”" } ?? "The microphone"
            return DictationNotice(kind: .silentMicrophone, message: "We couldn't hear you",
                                   detail: "\(source) stayed silent the whole time. Check that it isn't muted, or choose another microphone.",
                                   canRetry: false, canPasteAgain: false)
        }
        return DictationNotice(kind: .nothingHeard, message: "Didn't catch that",
                               detail: "No speech was recognized in the last recording.",
                               canRetry: hasRetainedAudio, canPasteAgain: false)
    }

    /// Peak microphone level (0…1 over −60…0 dBFS) below which a recording counts as silent.
    /// A quiet room sits near 0.25; a muted or disconnected input reads close to 0.
    static let silenceLevel: Float = 0.1

    /// Recordings shorter than this are accidental taps, so cancelling them offers no Undo.
    static let minimumUndoSeconds: Double = 1

    static func cancelled() -> DictationNotice {
        DictationNotice(kind: .cancelled, message: "Cancelled",
                        detail: "Nothing was typed. Undo transcribes what you said and types it.",
                        canRetry: true, canPasteAgain: false)
    }

    static func insertionFailed(_ reason: String, canPasteAgain: Bool) -> DictationNotice {
        DictationNotice(kind: .insertion, message: "Couldn't type it",
                        detail: reason + " The text is saved in HushKey.",
                        canRetry: false, canPasteAgain: canPasteAgain)
    }

    static func pasteUnconfirmed(_ reason: String, canPasteAgain: Bool) -> DictationNotice {
        DictationNotice(kind: .insertion, message: "Check the field first",
                        detail: reason + " The transcript is saved in HushKey. Check the destination before retrying, because another paste could duplicate it.",
                        canRetry: false, canPasteAgain: canPasteAgain)
    }

    static func focusLost(appName: String) -> DictationNotice {
        DictationNotice(kind: .focusLost, message: "Click back into \(appName)",
                        detail: "Paste again only types into the field you dictated from. Focus it in \(appName), then try again.",
                        canRetry: false, canPasteAgain: true)
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
    var mode: DictationMode
    var languageIdentifier: String
    var snippets: String
    var correctionRules: String
    var cleansFillers: Bool
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
        guard insertionEnabled else { return .unavailable("Turn on text insertion in Settings first.") }
        guard hasTarget else {
            return .unavailable("This dictation has no saved target field. Use Insert in HushKey instead.")
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
    private var buffers: [AVAudioPCMBuffer] = []
    private var seconds: Double = 0
    private var overflowed = false

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
        guard let copy = Self.copy(buffer) else { return }
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
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}

/// The card above the pill that shows live text, and keeps the final text up with Copy when
/// there was no text field to type into.
enum TranscriptCard {
    enum State: Equatable {
        case hidden
        case live(hint: String?)
        case finished(hint: String?)
    }

    static let noTargetHint = "No text box selected. Talk, then copy."

    static func state(isCapturing: Bool, hasTarget: Bool, transcript: String,
                      isCollapsed: Bool, keepsFinishedText: Bool) -> State {
        let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hint = hasTarget ? nil : noTargetHint
        if isCapturing {
            guard !isCollapsed, !hasTarget || hasText else { return .hidden }
            return .live(hint: hint)
        }
        return keepsFinishedText && hasText ? .finished(hint: hint) : .hidden
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
