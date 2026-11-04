import Foundation

/// Joins Speech results into one transcript across pauses.
///
/// On-device recognition on recent macOS silently starts a new transcription after a pause in the
/// same task: later partials hold only the new phrase. Tasks can also end on silence with an
/// error (often "No speech detected") and no final text. Either way, the phrase heard so far
/// must be kept, or everything said before the pause disappears.
struct TranscriptStitcher: Equatable {
    /// Phrases that are done and will not change.
    private(set) var committed = ""
    /// The phrase Speech is still revising.
    private(set) var current = ""
    private var currentStart: TimeInterval = 0
    private var currentEnd: TimeInterval = 0

    var text: String { Self.join(committed, current) }

    init(text: String = "") { committed = text }

    /// - Parameters:
    ///   - start: audio time of the first word in `partial`, if Speech reported timings.
    ///   - end: audio time just after the last word.
    mutating func update(partial: String, start: TimeInterval = 0, end: TimeInterval = 0) {
        let partial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        if !current.isEmpty, Self.isNewPhrase(partial, start: start, after: current,
                                              previousStart: currentStart, previousEnd: currentEnd) {
            commit()
        }
        current = partial
        currentStart = start
        currentEnd = end
    }

    /// The task finished (final result, silence, or error): keep what was heard.
    mutating func commit() {
        committed = Self.join(committed, current)
        current = ""
        currentStart = 0
        currentEnd = 0
    }

    static func isNewPhrase(_ partial: String, start: TimeInterval, after previous: String,
                            previousStart: TimeInterval, previousEnd: TimeInterval) -> Bool {
        // With timings: a revision starts where the phrase started; a new phrase starts after it ended.
        if start > 0, previousEnd > 0 {
            return start >= previousEnd - 0.05 && start > previousStart + 0.05
        }
        // Without timings: a revision keeps the opening word and rarely shrinks by much.
        let firstWord = { (text: String) in
            text.split(whereSeparator: \.isWhitespace).first.map {
                $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
            } ?? ""
        }
        return firstWord(partial) != firstWord(previous) && partial.count < previous.count
    }

    static func join(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        // Speech capitalizes a phrase it hears as a new sentence; give the one before it an ending.
        if let last = a.last, !".?!,;:…".contains(last), startsSentence(b) {
            return a + ". " + b
        }
        return a + " " + b
    }

    private static func startsSentence(_ text: String) -> Bool {
        guard let first = text.first, first.isUppercase else { return false }
        let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return !["I", "I'm", "I’m", "I'll", "I’ll", "I've", "I’ve", "I'd", "I’d"].contains(word)
    }
}
