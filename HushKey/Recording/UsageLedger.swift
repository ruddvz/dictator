import Foundation

/// Where a dictation went, for Insights. Contexts from the Style page, plus Code.
enum UsageCategory: String, CaseIterable, Codable {
    case work = "Work messages"
    case personal = "Personal messages"
    case email = "Email"
    case code = "Code"
    case other = "Other"

    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .personal: "bubble.left.and.bubble.right"
        case .email: "envelope"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "doc.text"
        }
    }

    static func category(mode: DictationMode, bundleIdentifier: String?) -> UsageCategory {
        if mode == .code { return .code }
        switch DictationContext.context(for: bundleIdentifier) {
        case .personal: return .personal
        case .work: return .work
        case .email: return .email
        case .other: return .other
        }
    }
}

/// One day's dictation totals. Counts only: no text, apps or audio.
struct DayUsage: Codable, Equatable {
    var words = 0
    var dictations = 0
    /// Microphone seconds, for words per minute.
    var seconds: Double = 0
    /// Words the local cleanup changed or removed (fillers, spoken corrections, rules).
    var wordsCleaned = 0
    /// Words by `UsageCategory.rawValue`.
    var categoryWords: [String: Int] = [:]
}

/// Lifetime dictation totals by day, kept on this Mac so Insights outlive the 50-entry history.
struct UsageLedger: Codable, Equatable {
    /// Days keyed "yyyy-MM-dd" in the user's calendar.
    var days: [String: DayUsage] = [:]

    /// A typical novel, for the "books" comparison.
    static let wordsPerBook = 90_000
    /// A typical typing speed, for the "faster than typing" comparison.
    static let typingWordsPerMinute = 40

    mutating func record(words: Int, seconds: Double?, wordsCleaned: Int, category: UsageCategory,
                         at date: Date = Date(), calendar: Calendar = .current) {
        guard words > 0 else { return }
        let key = Self.key(for: date, calendar: calendar)
        var day = days[key] ?? DayUsage()
        day.words += words
        day.dictations += 1
        day.seconds += max(0, seconds ?? 0)
        day.wordsCleaned += max(0, wordsCleaned)
        day.categoryWords[category.rawValue, default: 0] += words
        days[key] = day
    }

    var totalWords: Int { days.values.reduce(0) { $0 + $1.words } }
    var totalDictations: Int { days.values.reduce(0) { $0 + $1.dictations } }
    var wordsCleaned: Int { days.values.reduce(0) { $0 + $1.wordsCleaned } }

    /// Pace over days that measured microphone time.
    var wordsPerMinute: Int? {
        let timed = days.values.filter { $0.seconds >= 1 }
        let seconds = timed.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return nil }
        return Int((Double(timed.reduce(0) { $0 + $1.words }) / seconds * 60).rounded())
    }

    /// Words per category, largest first, with each one's share of the total.
    var categories: [(category: UsageCategory, words: Int, share: Double)] {
        var totals: [UsageCategory: Int] = [:]
        for day in days.values {
            for (name, words) in day.categoryWords {
                totals[UsageCategory(rawValue: name) ?? .other, default: 0] += words
            }
        }
        let sum = max(1, totals.values.reduce(0, +))
        return totals.filter { $0.value > 0 }
            .map { (category: $0.key, words: $0.value, share: Double($0.value) / Double(sum)) }
            .sorted { $0.words > $1.words }
    }

    /// Change in words this calendar month against last month, or nil without last month's data.
    func monthChange(now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let lastMonthDay = calendar.date(byAdding: .month, value: -1, to: now),
              let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDay) else { return nil }
        let current = words(in: thisMonth, calendar: calendar)
        let previous = words(in: lastMonth, calendar: calendar)
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }

    /// Consecutive days with a dictation, ending today or yesterday.
    func currentStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let active = activeDays(calendar: calendar)
        var day = calendar.startOfDay(for: now)
        if !active.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var streak = 0
        while active.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    func longestStreak(calendar: Calendar = .current) -> Int {
        let sorted = activeDays(calendar: calendar).sorted()
        var longest = 0, run = 0
        var previous: Date?
        for day in sorted {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// Dictations per day, for the heatmap.
    func dailyCounts(calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for (key, day) in days {
            if let date = Self.date(for: key, calendar: calendar) { counts[date] = day.dictations }
        }
        return counts
    }

    /// Words a cleanup changed: raw words that are missing from the final text, counted with repeats.
    static func wordsCleaned(raw: String, final: String) -> Int {
        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        var remaining = Dictionary(words(final).map { ($0, 1) }, uniquingKeysWith: +)
        var changed = 0
        for word in words(raw) {
            if let count = remaining[word], count > 0 { remaining[word] = count - 1 } else { changed += 1 }
        }
        return changed
    }

    /// Starts a ledger from the saved history the first time Insights is used.
    static func seeded(from entries: [DictationHistoryEntry], calendar: Calendar = .current) -> UsageLedger {
        var ledger = UsageLedger()
        for entry in entries {
            ledger.record(words: entry.wordCount, seconds: entry.duration,
                          wordsCleaned: entry.rawText.map { wordsCleaned(raw: $0, final: entry.text) } ?? 0,
                          category: .other, at: entry.createdAt, calendar: calendar)
        }
        return ledger
    }

    private func activeDays(calendar: Calendar) -> Set<Date> {
        Set(days.filter { $0.value.dictations > 0 }.compactMap { Self.date(for: $0.key, calendar: calendar) })
    }

    private func words(in interval: DateInterval, calendar: Calendar) -> Int {
        days.reduce(0) { sum, item in
            // DateInterval.contains includes the end, which is the next month's first day.
            guard let date = Self.date(for: item.key, calendar: calendar),
                  date >= interval.start, date < interval.end else { return sum }
            return sum + item.value.words
        }
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

enum UsageLedgerStore {
    static var url: URL { AppDataDirectory.url.appending(path: "usage.json") }

    static func load(from url: URL = url) -> UsageLedger? {
        switch LocalJSONArchive.load(UsageLedger.self, from: url) {
        case .loaded(let ledger): ledger
        case .missing, .unreadable: nil
        }
    }

    static func save(_ ledger: UsageLedger, to url: URL = url) throws {
        try LocalJSONArchive.save(ledger, protectingExistingAs: UsageLedger.self, to: url)
    }
}
