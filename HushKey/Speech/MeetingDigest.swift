import Foundation

/// Pure helpers for the meeting result: the pill's clock, the Markdown that Copy and Export
/// share, and a plain on-device fallback (key sentences and commitments picked from the
/// transcript) for Macs without Apple's on-device language model. Nothing here leaves the Mac.
enum MeetingDigest {
    /// Meetings shorter than this are shown as a transcript only: there is nothing to condense.
    static let minimumWordsToSummarize = 40
    /// Sentences kept by the fallback summary, and action items shown on the pill's card.
    static let fallbackSummarySentences = 3
    static let maximumFallbackActionItems = 8

    // MARK: Clock

    /// "0:07", "12:03", "1:02:03": the pill's running timer and the card's length.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }

    /// "Under a minute", "12 min", "1 h 5 min": a meeting's length in words.
    static func lengthLabel(_ seconds: TimeInterval) -> String {
        let minutes = seconds.isFinite ? max(0, Int(seconds)) / 60 : 0
        if minutes == 0 { return "Under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func isLongEnoughToSummarize(_ transcript: String) -> Bool {
        wordCount(transcript) >= minimumWordsToSummarize
    }

    // MARK: Markdown (Copy and Export)

    static func markdown(for note: MeetingNote) -> String {
        var lines = ["# \(note.title.trimmingCharacters(in: .whitespacesAndNewlines))", ""]
        let date = note.createdAt.formatted(date: .complete, time: .shortened)
        lines += ["\(date) · \(lengthLabel(note.duration))", ""]
        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { lines += ["## Summary", "", summary, ""] }
        let items = actionItems(from: note.actionItems)
        if !items.isEmpty {
            lines += ["## Action items", ""] + items.map { "- [ ] \($0)" } + [""]
        }
        lines += ["## Transcript", "", note.transcript.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        return lines.joined(separator: "\n")
    }

    /// A file name for Export: the title without characters Finder or the shell trip over.
    static func filename(for title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = title.unicodeScalars.map { banned.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
        let short = cleaned.count > 80 ? String(cleaned.prefix(80)) : cleaned
        return (short.isEmpty ? "Meeting notes" : short) + ".md"
    }

    // MARK: Action items

    /// One task per line, from the model's bullets or the fallback's, without bullet marks.
    /// The model's "No clear action items." means none.
    static func actionItems(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) != "no clear action items"
        else { return [] }
        return trimmed.components(separatedBy: .newlines).compactMap { line in
            var item = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "* ", "- ", "• ", "– "] where item.hasPrefix(prefix) {
                item.removeFirst(prefix.count)
                break
            }
            if let match = item.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
                item.removeSubrange(match)
            }
            item = item.trimmingCharacters(in: .whitespaces)
            // Headings the model sometimes adds ("Action items:") are not tasks.
            guard !item.isEmpty, !(item.hasSuffix(":") && wordCount(item) <= 4) else { return nil }
            return item.replacingOccurrences(of: "**", with: "")
        }
    }

    // MARK: Fallback, without a language model

    /// Sentences, split on end punctuation and line breaks.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sentence, _, _, _ in
            guard let sentence else { return }
            for line in sentence.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if wordCount(clean) >= 3 { result.append(clean) }
            }
        }
        return result
    }

    /// The few sentences that share the most content words with the rest of the meeting, kept in
    /// the order they were said. A plain, honest stand-in for a summary: nothing is reworded.
    static func fallbackSummary(from transcript: String, keep: Int = fallbackSummarySentences) -> String {
        let all = sentences(in: transcript)
        guard all.count > keep else { return all.map { "- \($0)" }.joined(separator: "\n") }
        var frequency: [String: Int] = [:]
        let tokenized = all.map(contentWords)
        for words in tokenized { for word in Set(words) { frequency[word, default: 0] += 1 } }
        let scored = tokenized.enumerated().map { index, words -> (Int, Double) in
            guard !words.isEmpty else { return (index, 0) }
            let score = words.reduce(0.0) { $0 + Double(frequency[$1] ?? 0) }
            // Long sentences shouldn't win on length alone.
            return (index, score / Double(max(words.count, 6)).squareRoot())
        }
        let picked = scored.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.prefix(keep).map(\.0).sorted()
        return picked.map { "- \(all[$0])" }.joined(separator: "\n")
    }

    /// Sentences where someone commits to, asks for, or schedules something.
    static func fallbackActionItems(from transcript: String) -> [String] {
        var seen = Set<String>()
        return sentences(in: transcript).filter { sentence in
            let lower = " " + sentence.lowercased().replacingOccurrences(of: "’", with: "'") + " "
            guard commitmentCues.contains(where: lower.contains) else { return false }
            return seen.insert(lower).inserted
        }.prefix(maximumFallbackActionItems).map { $0 }
    }

    private static let commitmentCues = [
        " i'll ", " i will ", " we'll ", " we will ", " you'll ", " he'll ", " she'll ", " they'll ",
        " i'm going to ", " we're going to ", " i am going to ", " we are going to ",
        " need to ", " needs to ", " have to ", " has to ", " should ", " let's ", " let us ",
        " can you ", " could you ", " would you ", " please ", " make sure ", " remind ",
        " follow up", " follow-up", " action item", " to-do", " todo", " next step", " deadline",
        " by monday", " by tuesday", " by wednesday", " by thursday", " by friday", " by tomorrow",
        " by end of", " by the end of", " by next ", " send ", " schedule ", " set up ",
    ]

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "with", "is",
        "are", "was", "were", "be", "been", "it", "its", "it's", "that", "this", "these", "those", "i",
        "you", "we", "they", "he", "she", "me", "us", "them", "my", "our", "your", "their", "do", "does",
        "did", "have", "has", "had", "not", "just", "like", "yeah", "yes", "okay", "ok", "um", "uh",
        "so", "if", "then", "there", "what", "which", "who", "how", "can", "will", "would", "could",
        "about", "from", "as", "by", "all", "really", "think", "know", "going", "get", "got", "one",
        "i'm", "we're", "you're", "that's", "don't", "kind", "sort", "right", "well", "also", "very",
    ]

    private static func contentWords(_ sentence: String) -> [String] {
        sentence.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
