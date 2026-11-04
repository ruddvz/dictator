import AppKit
import Foundation

/// Decides which words of a live transcript are settled enough to type while the person is still
/// talking. Typed words are never taken back, so a word is final only once Speech has stopped
/// revising it: after a pause, once it has stayed the same for a moment with newer words after it,
/// or when too many unsettled words pile up.
///
/// The finalize-on-pause / stops-changing / window-cap rule is adapted from
/// dimastatz/whisper-flow (MIT); see NOTICE.md. The code is HushKey's own.
struct LivePhraseFinalizer: Equatable {
    struct Rules: Equatable {
        /// A word unchanged for this long, with `holdbackWords` newer words after it, is final.
        var stableSeconds: TimeInterval = 0.8
        /// No change to the transcript for this long: every word heard is final.
        var pauseSeconds: TimeInterval = 1.0
        /// The newest words Speech revises most; outside a pause they wait.
        var holdbackWords = 2
        /// Past this many unsettled words, all but the holdback are final even if still changing.
        var maximumPendingWords = 14
        /// Outside a pause, type at least this many words at once unless a phrase ends in punctuation,
        /// so text arrives in phrases rather than one word at a time.
        var minimumPhraseWords = 3
    }

    /// Words to type now. `leadingPunctuation` belongs to the word typed before: Speech often adds
    /// a full stop or comma to it once the next phrase starts, and it can still be appended.
    struct Phrase: Equatable {
        var leadingPunctuation = ""
        var words = ""

        var isEmpty: Bool { leadingPunctuation.isEmpty && words.isEmpty }
    }

    let rules: Rules
    /// Every word handed out so far, as written then (after any punctuation added later).
    private(set) var finalizedWords: [String] = []
    /// Words after the finalized ones, still subject to revision.
    private(set) var pendingWords: [String] = []
    /// When each pending word last changed.
    private var pendingSince: [TimeInterval] = []
    /// When the transcript last changed at all.
    private var lastChange: TimeInterval?
    /// The latest transcript's version of the last finalized word, for punctuation added later.
    private var anchorWord: String?

    init(rules: Rules = Rules()) { self.rules = rules }

    var hasFinalized: Bool { !finalizedWords.isEmpty }

    /// Feeds the whole live transcript as it stands at `time`; returns what became final, if anything.
    mutating func update(transcript: String, at time: TimeInterval) -> Phrase? {
        let words = Self.words(in: transcript)
        let start = alignedStart(in: words)
        anchorWord = start > 0 ? words[start - 1] : nil
        let pending = Array(words[start...])
        let kept = Self.commonPrefixCount(pending, pendingWords)
        if kept != pending.count || kept != pendingWords.count || lastChange == nil {
            lastChange = time
        }
        pendingSince = Array(pendingSince.prefix(kept)) + Array(repeating: time, count: pending.count - kept)
        pendingWords = pending
        return advance(to: time)
    }

    /// Called on a timer as well, since a pause produces no new transcript to react to.
    mutating func advance(to time: TimeInterval) -> Phrase? {
        let count = finalizableCount(at: time)
        guard count > 0 || (isPaused(at: time) && pendingPunctuation != nil) else { return nil }
        return take(count)
    }

    /// The dictation ended: everything not yet typed, aligned against the final transcript.
    mutating func finish(transcript: String) -> Phrase {
        let words = Self.words(in: transcript)
        let start = alignedStart(in: words)
        anchorWord = start > 0 ? words[start - 1] : nil
        pendingWords = Array(words[start...])
        pendingSince = Array(repeating: 0, count: pendingWords.count)
        return take(pendingWords.count)
    }

    // MARK: - Rule

    func isPaused(at time: TimeInterval) -> Bool {
        guard let lastChange else { return false }
        return time - lastChange >= rules.pauseSeconds
    }

    /// How many leading pending words are final at `time`.
    func finalizableCount(at time: TimeInterval) -> Int {
        guard !pendingWords.isEmpty else { return 0 }
        if isPaused(at: time) { return pendingWords.count }
        let open = max(0, pendingWords.count - rules.holdbackWords)
        let stable = pendingSince.prefix(open).prefix { time - $0 >= rules.stableSeconds }.count
        let capped = pendingWords.count > rules.maximumPendingWords ? open : stable
        guard capped > 0 else { return 0 }
        // Prefer to stop at the end of a clause; otherwise wait for a few words.
        if let clauseEnd = pendingWords.prefix(capped).lastIndex(where: Self.endsClause) {
            return clauseEnd + 1
        }
        return capped >= rules.minimumPhraseWords || capped == open && pendingWords.count > rules.maximumPendingWords
            ? capped : 0
    }

    // MARK: - Internals

    private var pendingPunctuation: String? {
        guard let last = finalizedWords.last, let anchorWord,
              Self.normalized(anchorWord) == Self.normalized(last) else { return nil }
        let added = Self.trailingPunctuation(anchorWord)
        guard !added.isEmpty, Self.trailingPunctuation(last).isEmpty else { return nil }
        return added
    }

    private mutating func take(_ count: Int) -> Phrase {
        var phrase = Phrase()
        if let punctuation = pendingPunctuation, let anchorWord {
            phrase.leadingPunctuation = punctuation
            finalizedWords[finalizedWords.count - 1] = anchorWord
        }
        let taken = Array(pendingWords.prefix(count))
        phrase.words = taken.joined(separator: " ")
        finalizedWords += taken
        pendingWords.removeFirst(taken.count)
        pendingSince.removeFirst(min(taken.count, pendingSince.count))
        if let last = taken.last { anchorWord = last }
        return phrase
    }

    /// Where the words after the finalized ones start in a fresh transcript. Speech can merge or
    /// split earlier words, so this matches the last few finalized words near where they should be.
    private func alignedStart(in words: [String]) -> Int {
        let typed = finalizedWords.count
        guard typed > 0 else { return 0 }
        let normalizedWords = words.map(Self.normalized)
        for span in [min(3, typed), 1] {
            let tail = finalizedWords.suffix(span).map(Self.normalized)
            let lower = max(span, typed - 6), upper = min(words.count, typed + 6)
            guard lower <= upper else { continue }
            let candidates = (lower...upper).sorted { abs($0 - typed) < abs($1 - typed) }
            if let match = candidates.first(where: { Array(normalizedWords[($0 - span)..<$0]) == tail }) {
                return match
            }
        }
        return min(typed, words.count)
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    static func trailingPunctuation(_ word: String) -> String {
        String(word.reversed().prefix { ".,;:!?…".contains($0) }.reversed())
    }

    static func endsClause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ".,;:!?…".contains(last)
    }

    static func commonPrefixCount(_ a: [String], _ b: [String]) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}

/// Whether typing live is safe for this dictation's field. Anything else types at the end, as before.
enum LiveTypingEligibility: Equatable {
    case eligible
    case settingOff
    case noReadableField
    case electron
    case parakeet
    case codeMode

    static func decide(enabled: Bool, hasReadableField: Bool, isElectron: Bool,
                       usesParakeet: Bool, mode: DictationMode) -> LiveTypingEligibility {
        guard enabled else { return .settingOff }
        guard !usesParakeet else { return .parakeet }
        guard mode != .code else { return .codeMode }
        guard hasReadableField else { return .noReadableField }
        guard !isElectron else { return .electron }
        return .eligible
    }

    /// Electron rebuilds its text boxes and its accessibility read-back lags, so a live insert
    /// can't be confirmed there.
    static func isElectron(_ app: NSRunningApplication?) -> Bool {
        guard let url = app?.bundleURL else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }
}

/// One dictation's live typing: what was typed, what is left, and whether it can go on.
struct LiveTypingSession {
    enum State: Equatable {
        /// Every phrase so far went in and was read back.
        case active
        /// A phrase was refused (focus moved, or the field changed); nothing more is typed.
        case stopped
        /// The field changed but HushKey couldn't confirm the exact text; nothing more is typed.
        case uncertain
    }

    var finalizer = LivePhraseFinalizer()
    var state = State.active
    /// Text confirmed in the field, in order.
    private(set) var typed = ""
    /// Text after the point live typing stopped, for the card.
    private(set) var untyped = ""
    private let startedAt: TimeInterval

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) { self.startedAt = startedAt }

    func elapsed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval { now - startedAt }

    /// Something reached the field, or may have, so the end must not type the whole text again.
    var hasDelivered: Bool { !typed.isEmpty || state == .uncertain }

    /// The dictation as it reads in the field, followed by anything that was not typed.
    var text: String { Self.joined(typed, untyped) }

    mutating func recordTyped(_ value: String) { typed = Self.joined(typed, value) }
    mutating func recordUntyped(_ value: String) { untyped = Self.joined(untyped, value) }

    static func joined(_ first: String, _ second: String) -> String {
        guard !first.isEmpty else { return second }
        return first + TextInsertionService.spaced(second, after: first.last)
    }

    /// Cleanup trims a phrase's ends, which would drop a spoken "new line" at a phrase boundary.
    static func keepingLineBreaks(of raw: String, mode: DictationMode, in processed: String) -> String {
        let formatted = DictationModeFormatter.format(raw, mode: mode)
        let leading = String(formatted.prefix(while: \.isNewline))
        let trailing = String(formatted.reversed().prefix(while: \.isNewline))
        var result = processed
        if !leading.isEmpty, !result.hasPrefix("\n") { result = leading + result }
        if !trailing.isEmpty, !result.hasSuffix("\n") { result += trailing }
        return result
    }
}
