import Foundation

/// "Your voice": a profile read from the dictation history and usage ledger on this Mac.
/// Pure and deterministic, so it is tested without the app; nothing here leaves the Mac.
///
/// The cards unlock one at a time as dictations add up (`Card.unlocksAt`), the first after
/// `firstUnlock` dictations. Before that the view shows an honest count of what's left.
struct VoiceProfile: Equatable {
    /// Speaking pace by words per minute of microphone time (pauses included, so lower than
    /// conversational speech).
    enum Pace: String, CaseIterable, Equatable {
        case unhurried = "Unhurried"
        case steady = "Steady"
        case quick = "Quick"
        case rapid = "Rapid"

        /// Lower bound in wpm for each pace above `unhurried`.
        static let steadyFrom = 100
        static let quickFrom = 130
        static let rapidFrom = 160

        init(wordsPerMinute wpm: Int) {
            switch wpm {
            case ..<Self.steadyFrom: self = .unhurried
            case ..<Self.quickFrom: self = .steady
            case ..<Self.rapidFrom: self = .quick
            default: self = .rapid
            }
        }

        var detail: String {
            switch self {
            case .unhurried: "You take your time and choose your words."
            case .steady: "An even, easy pace, like talking to a friend."
            case .quick: "Brisk and fluent. You think out loud."
            case .rapid: "Fast talker. Your words outrun the keyboard."
            }
        }
    }

    enum TimeOfDay: String, Equatable {
        case earlyBird = "Early bird"
        case midday = "Midday regular"
        case evening = "Evening regular"
        case nightOwl = "Night owl"

        /// Classifies by the middle hour of the busiest window.
        init(hour: Int) {
            switch hour {
            case 5..<11: self = .earlyBird
            case 11..<17: self = .midday
            case 17..<22: self = .evening
            default: self = .nightOwl
            }
        }
    }

    /// The busiest `PeakHours.window`-hour stretch of the day, which may wrap past midnight.
    struct PeakHours: Equatable {
        static let window = 3
        var startHour: Int
        var dictations: Int
        var share: Double
        var timeOfDay: TimeOfDay { TimeOfDay(hour: (startHour + 1) % 24) }
        var endHour: Int { (startHour + Self.window) % 24 }
        var label: String { "\(VoiceProfile.hourLabel(startHour))–\(VoiceProfile.hourLabel(endHour))" }
    }

    struct Count: Equatable {
        var text: String
        /// For a phrase, the dictations it appears in; for a correction, the times it was fixed.
        var count: Int
    }

    enum Card: Int, CaseIterable, Comparable {
        case pace, cleanup, peakHours, phrase

        /// Lifetime dictations needed before the card shows.
        var unlocksAt: Int {
            switch self {
            case .pace: VoiceProfile.firstUnlock
            case .cleanup: 20
            case .peakHours: 30
            case .phrase: 40
            }
        }

        var title: String {
            switch self {
            case .pace: "Your pace"
            case .cleanup: "What cleanup fixed"
            case .peakHours: "When you talk"
            case .phrase: "Your catchphrase"
            }
        }

        static func < (lhs: Card, rhs: Card) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let firstUnlock = 10
    /// A typical typing speed, for time saved.
    static let typingWordsPerMinute = UsageLedger.typingWordsPerMinute
    /// Peak hours need this many dated dictations in history to say anything.
    static let minimumForPeakHours = 5
    /// A phrase must recur in this many separate dictations.
    static let minimumPhraseDictations = 3

    /// Lifetime dictations, from the ledger (history keeps only the latest 50).
    let dictations: Int
    /// History entries the text-based cards read from.
    let historyCount: Int
    let wordsPerMinute: Int?
    let pace: Pace?
    /// Typing time the words would have taken, minus the time spent saying them. Never negative.
    let minutesSaved: Double
    let peakHours: PeakHours?
    let catchphrase: Count?
    /// Filler words and stutters cleanup removed, across `historyCount` dictations.
    let fillersRemoved: Int
    /// The word cleanup or your replacements fixed most often, shown as it was fixed to.
    let mostCorrected: Count?

    /// `readingText: false` skips the catchphrase and cleanup cards, which diff every entry's
    /// text, for surfaces such as Home that re-render often and only need pace, hours and time.
    init(entries: [DictationHistoryEntry], ledger: UsageLedger, readingText: Bool = true,
         calendar: Calendar = .current) {
        dictations = max(ledger.totalDictations, entries.count)
        historyCount = entries.count
        let wpm = ledger.wordsPerMinute ?? DictationStats(entries: entries, calendar: calendar).wordsPerMinute
        wordsPerMinute = wpm.flatMap { $0 > 0 ? $0 : nil }
        pace = wordsPerMinute.map(Pace.init(wordsPerMinute:))
        minutesSaved = Self.minutesSaved(ledger: ledger)
        peakHours = Self.peakHours(entries.map(\.createdAt), calendar: calendar)
        catchphrase = readingText ? Self.catchphrase(entries.map(\.text)) : nil
        let cleanup = readingText ? Self.cleanup(entries) : (fillers: 0, mostCorrected: nil)
        fillersRemoved = cleanup.fillers
        mostCorrected = cleanup.mostCorrected
    }

    // MARK: Unlocking

    func isUnlocked(_ card: Card) -> Bool { dictations >= card.unlocksAt }

    var unlockedCards: [Card] { Card.allCases.filter(isUnlocked) }

    /// The next card to unlock and how many dictations it still needs.
    var nextUnlock: (card: Card, remaining: Int)? {
        Card.allCases.first { !isUnlocked($0) }.map { ($0, $0.unlocksAt - dictations) }
    }

    // MARK: Time saved

    /// Words ÷ 40 wpm minus speaking time, over days that measured microphone time, so words
    /// with no recorded speaking time can't inflate it.
    static func minutesSaved(ledger: UsageLedger) -> Double {
        let timed = ledger.days.values.filter { $0.seconds >= 1 }
        let words = timed.reduce(0) { $0 + $1.words }
        let seconds = timed.reduce(0) { $0 + $1.seconds }
        return max(0, Double(words) / Double(typingWordsPerMinute) - seconds / 60)
    }

    /// "about 25 min saved", "about 2 h saved", or nil under a minute.
    var timeSavedText: String? { Self.timeSavedText(minutes: minutesSaved) }

    static func timeSavedText(minutes: Double) -> String? {
        guard minutes.isFinite, minutes >= 1 else { return nil }
        if minutes < 59.5 { return "about \(Int(minutes.rounded())) min saved" }
        let hours = minutes / 60
        // Whole hours from 10 h, halves below so "1.5 h" stays honest without false precision.
        let shown = hours >= 10 ? hours.rounded() : (hours * 2).rounded() / 2
        let text = shown == shown.rounded() ? String(Int(shown)) : shown.formatted(.number.precision(.fractionLength(1)))
        return "about \(text) h saved"
    }

    // MARK: Peak hours

    static func peakHours(_ dates: [Date], calendar: Calendar) -> PeakHours? {
        guard dates.count >= minimumForPeakHours else { return nil }
        var byHour = [Int](repeating: 0, count: 24)
        for date in dates { byHour[calendar.component(.hour, from: date)] += 1 }
        var best = (start: 0, count: -1)
        for start in 0..<24 {
            let count = (0..<PeakHours.window).reduce(0) { $0 + byHour[(start + $1) % 24] }
            if count > best.count { best = (start, count) }
        }
        return PeakHours(startHour: best.start, dictations: best.count,
                         share: Double(best.count) / Double(dates.count))
    }

    /// "6 AM", "noon", "midnight".
    static func hourLabel(_ hour: Int) -> String {
        switch hour % 24 {
        case 0: "midnight"
        case 12: "noon"
        case let h where h < 12: "\(h) AM"
        case let h: "\(h - 12) PM"
        }
    }

    // MARK: Catchphrase

    /// Words that can't start or end a catchphrase.
    private static let connectors: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "with", "so",
        "is", "are", "was", "be", "it", "that", "this", "as", "by", "from", "if",
    ]
    /// Function words; a phrase made only of these says nothing about you.
    private static let functionWords: Set<String> = connectors.union([
        "i", "you", "we", "he", "she", "they", "me", "us", "him", "her", "them", "my", "your", "our",
        "its", "their", "do", "does", "did", "not", "no", "can", "will", "would", "could", "should",
        "have", "has", "had", "were", "been", "am", "i'm", "it's", "there", "then", "than", "what",
        "just", "up", "out", "about", "into", "all", "some", "any",
        "don't", "doesn't", "didn't", "can't", "won't", "isn't", "aren't", "wasn't", "i'll", "i've",
        "i'd", "you're", "we're", "they're", "that's", "there's", "let's", "gonna", "get", "got", "go",
    ])

    /// The 2–4 word phrase found in the most separate dictations (at least three), preferring
    /// the longer phrase on a tie so "let me know" wins over "let me".
    static func catchphrase(_ texts: [String]) -> Count? {
        var counts: [String: Int] = [:]
        for text in texts {
            let words = tokens(text).map { $0.lowercased() }
            var seen = Set<String>()
            for n in 2...4 where words.count >= n {
                for start in 0...(words.count - n) {
                    let gram = Array(words[start..<(start + n)])
                    guard !connectors.contains(gram[0]), !connectors.contains(gram[n - 1]),
                          gram.contains(where: { !functionWords.contains($0) && !fillerWords.contains($0) }),
                          Set(gram).count > 1 else { continue }
                    seen.insert(gram.joined(separator: " "))
                }
            }
            for gram in seen { counts[gram, default: 0] += 1 }
        }
        let best = counts.filter { $0.value >= minimumPhraseDictations }.max { a, b in
            if a.value != b.value { return a.value < b.value }
            let (na, nb) = (a.key.split(separator: " ").count, b.key.split(separator: " ").count)
            if na != nb { return na < nb }
            return a.key > b.key
        }
        return best.map { Count(text: displayPhrase($0.key), count: $0.value) }
    }

    /// Restores the capital on "I" and its contractions, which lowercasing for counting lost.
    static func displayPhrase(_ phrase: String) -> String {
        phrase.split(separator: " ").map { word in
            word == "i" || word.hasPrefix("i'") ? "I" + word.dropFirst() : String(word)
        }.joined(separator: " ")
    }

    // MARK: Cleanup

    /// Single-word fillers. A removed "like" or "so" was a filler, or cleanup would have kept it.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "ah", "er", "erm", "eh", "hmm", "hm", "mm",
        "like", "basically", "literally", "actually", "so", "well", "okay", "right",
    ]
    /// Longest raw or fixed side of a substitution that still counts as one corrected word.
    private static let maximumCorrectionWords = 3
    /// Dictations longer than this skip the word diff, to keep the profile cheap.
    private static let maximumDiffWords = 800

    static func cleanup(_ entries: [DictationHistoryEntry]) -> (fillers: Int, mostCorrected: Count?) {
        var fillers = 0
        var corrections: [String: (shown: String, count: Int)] = [:]
        for entry in entries {
            guard let raw = entry.rawText else { continue }
            let rawWords = tokens(raw), finalWords = tokens(entry.text)
            guard rawWords.count <= maximumDiffWords, finalWords.count <= maximumDiffWords else { continue }
            for gap in gaps(rawWords.map { $0.lowercased() }, finalWords.map { $0.lowercased() }) {
                if gap.inserted.isEmpty {
                    // Pure deletions: count fillers and stutters ("I I", "the the").
                    for index in gap.deleted {
                        let word = rawWords[index].lowercased()
                        let previous = index > 0 ? rawWords[index - 1].lowercased() : nil
                        let next = index + 1 < rawWords.count ? rawWords[index + 1].lowercased() : nil
                        if fillerWords.contains(word) || word == previous || word == next { fillers += 1 }
                    }
                } else if !gap.deleted.isEmpty,
                          gap.deleted.count <= maximumCorrectionWords, gap.inserted.count <= maximumCorrectionWords,
                          !gap.deleted.allSatisfy({ fillerWords.contains(rawWords[$0].lowercased()) }) {
                    // A substitution: a vocabulary snap or one of your replacements.
                    let shown = gap.inserted.map { finalWords[$0] }.joined(separator: " ")
                    let key = shown.lowercased()
                    corrections[key, default: (shown, 0)].count += 1
                }
            }
        }
        let best = corrections.max { a, b in
            a.value.count != b.value.count ? a.value.count < b.value.count : a.key > b.key
        }
        return (fillers, best.map { Count(text: $0.value.shown, count: $0.value.count) })
    }

    /// Words with their case, split like `UsageLedger.wordsCleaned`.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" })
            .map { String($0).replacingOccurrences(of: "’", with: "'") }
    }

    /// Runs where `raw` and `final` differ, from a longest-common-subsequence alignment:
    /// indexes into `raw` that were dropped and into `final` that were added.
    static func gaps(_ raw: [String], _ final: [String]) -> [(deleted: [Int], inserted: [Int])] {
        let n = raw.count, m = final.count
        // lcs[i][j] = LCS length of raw[i...] and final[j...].
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = raw[i] == final[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var result: [(deleted: [Int], inserted: [Int])] = []
        var deleted: [Int] = [], inserted: [Int] = []
        func flush() {
            if !deleted.isEmpty || !inserted.isEmpty { result.append((deleted, inserted)) }
            deleted = []; inserted = []
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, raw[i] == final[j] {
                flush(); i += 1; j += 1
            } else if j >= m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                deleted.append(i); i += 1
            } else {
                inserted.append(j); j += 1
            }
        }
        flush()
        return result
    }
}
