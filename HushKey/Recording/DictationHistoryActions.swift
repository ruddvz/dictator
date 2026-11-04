import Foundation

/// Whether a History row action can run now. `hidden` leaves it out of the menu; `unavailable`
/// shows it greyed out with the reason as its title ("Cannot retry while dictating").
enum DictationHistoryActionState: Equatable {
    case hidden
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
}

/// A deleted History entry, kept in memory for a few seconds so Delete can be undone.
/// The deletion is already saved; Undo writes the entry back where it was.
struct DeletedDictation: Equatable {
    var entry: DictationHistoryEntry
    /// Where it sat in the newest-first list when it was deleted.
    var index: Int
    var deletedAt: Date = Date()

    /// How long the "Deleted · Undo" bar stays up.
    static let undoSeconds: TimeInterval = 6

    /// The list with the entry back in its old place. An entry with the same ID that has come
    /// back some other way is replaced rather than duplicated, and the list keeps its limit.
    func restoring(into entries: [DictationHistoryEntry], limit: Int = 50) -> [DictationHistoryEntry] {
        var remaining = entries.filter { $0.id != entry.id }
        remaining.insert(entry, at: min(max(0, index), remaining.count))
        return Array(remaining.prefix(max(0, limit)))
    }
}

extension DictationHistoryEntry {
    /// The entry shows what the recognizer heard, before cleanup, and remembers the cleaned
    /// text so the change can be redone. Nil when there is no different original to go back to.
    func undoingCleanup() -> DictationHistoryEntry? {
        guard cleanedText == nil, let rawText, !rawText.isEmpty, rawText != text else { return nil }
        var copy = self
        copy.cleanedText = text
        copy.text = rawText
        return copy
    }

    /// Puts the cleaned text back after `undoingCleanup()`.
    func redoingCleanup() -> DictationHistoryEntry? {
        guard let cleanedText, !cleanedText.isEmpty else { return nil }
        var copy = self
        copy.text = cleanedText
        copy.cleanedText = nil
        return copy
    }

    /// "Slack · 0:12 · 34 words": the app it went to, how long you spoke, and its length.
    var metaLine: String {
        var parts: [String] = []
        if let appName, !appName.isEmpty { parts.append(appName) }
        if let duration, duration >= 0.5 {
            let seconds = Int(duration.rounded())
            parts.append(seconds < 60 ? "\(seconds) s" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))")
        }
        parts.append(wordCount == 1 ? "1 word" : "\(wordCount) words")
        return parts.joined(separator: " · ")
    }
}

/// When History can run a dictation's kept audio through the other speech engine.
/// Audio is held only in memory, for the latest dictation, until the next one starts or the app quits.
enum DictationRetranscribeGate {
    static let busyReason = "Cannot retry while dictating"
    static let audioGoneReason = "Audio no longer available"

    /// - Parameters:
    ///   - hasAudio: this entry's audio is still held in memory.
    ///   - hadAudio: this entry's audio was held earlier this session and has since been dropped.
    ///   - otherEngineProblem: why the other engine can't run (not downloaded, no permission), if so.
    static func state(hasAudio: Bool, hadAudio: Bool, isBusy: Bool,
                      otherEngineProblem: String?) -> DictationHistoryActionState {
        guard hasAudio else { return hadAudio ? .unavailable(audioGoneReason) : .hidden }
        if isBusy { return .unavailable(busyReason) }
        if let otherEngineProblem { return .unavailable(otherEngineProblem) }
        return .available
    }
}

/// When History's "Paste again" can retype a dictation into the field it came from.
/// Only the latest dictation remembers its field, and only until the next one starts.
enum DictationHistoryPasteGate {
    static func state(isLatestDictation: Bool, hasTarget: Bool, textMatches: Bool,
                      isBusy: Bool, alreadyInserted: Bool, insertionEnabled: Bool) -> DictationHistoryActionState {
        guard isLatestDictation, hasTarget, textMatches else { return .hidden }
        if isBusy { return .unavailable("Cannot paste while dictating") }
        if alreadyInserted { return .unavailable("Already pasted once") }
        if !insertionEnabled { return .unavailable("Text insertion is off") }
        return .available
    }
}
