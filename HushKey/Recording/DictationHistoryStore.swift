import Foundation

struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var text: String
    var rawText: String?
    /// Seconds the microphone was live for this dictation; absent for restored or older entries.
    var duration: TimeInterval?

    init(id: UUID = UUID(), createdAt: Date = Date(), text: String, rawText: String? = nil,
         duration: TimeInterval? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.rawText = rawText
        self.duration = duration
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Local, history-derived numbers for the Dictation home. Nothing leaves the Mac.
struct DictationStats: Equatable {
    var totalWords = 0
    var dictations = 0
    /// Average speaking pace across entries with a measured duration.
    var wordsPerMinute: Int?
    /// Consecutive days with at least one dictation, ending today or yesterday.
    var dayStreak = 0

    init(entries: [DictationHistoryEntry], now: Date = Date(), calendar: Calendar = .current) {
        dictations = entries.count
        totalWords = entries.reduce(0) { $0 + $1.wordCount }

        let timed = entries.filter { ($0.duration ?? 0) >= 1 }
        let timedSeconds = timed.reduce(0) { $0 + ($1.duration ?? 0) }
        if timedSeconds > 0 {
            let words = timed.reduce(0) { $0 + $1.wordCount }
            wordsPerMinute = Int((Double(words) / timedSeconds * 60).rounded())
        }

        let days = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        while days.contains(day) {
            dayStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
    }
}

enum DictationHistoryStore {
    private static let fileManager = FileManager.default

    static var url: URL {
        AppDataDirectory.url.appending(path: "dictation-history.json")
    }

    static func containsFile(at url: URL = url) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    static func load() -> [DictationHistoryEntry] {
        load(from: url) ?? []
    }

    static func load(from url: URL) -> [DictationHistoryEntry]? {
        switch loadState(from: url) {
        case .loaded(let entries): entries
        case .missing, .unreadable: nil
        }
    }

    static func loadState(from url: URL) -> JSONArchiveLoad<[DictationHistoryEntry]> {
        LocalJSONArchive.load([DictationHistoryEntry].self, from: url)
    }

    static func save(_ entries: [DictationHistoryEntry]) throws {
        try save(entries, to: url)
    }

    static func save(_ entries: [DictationHistoryEntry], to url: URL) throws {
        try LocalJSONArchive.save(entries, protectingExistingAs: [DictationHistoryEntry].self, to: url)
    }

    static func replaceAfterExplicitImport(_ entries: [DictationHistoryEntry], to url: URL) throws {
        try LocalJSONArchive.replaceAfterExplicitRecovery(entries,
                                                          preservingExistingAs: [DictationHistoryEntry].self,
                                                          to: url)
    }

    static func upsertingAndSaving(_ entry: DictationHistoryEntry,
                                   to url: URL,
                                   existing entries: [DictationHistoryEntry],
                                   limit: Int = 50) throws -> [DictationHistoryEntry] {
        var savedEntry = entry
        var remaining = entries
        if let existingIndex = remaining.firstIndex(where: { $0.id == entry.id }) {
            savedEntry.createdAt = remaining[existingIndex].createdAt
            remaining.remove(at: existingIndex)
        }
        let updated = Array(([savedEntry] + remaining).prefix(max(0, limit)))
        try save(updated, to: url)
        return updated
    }

    static func delete(at url: URL = url) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum DictationHistoryClearGate {
    nonisolated static func canClear(isStarting: Bool,
                                     isRecording: Bool,
                                     isFinalizing: Bool,
                                     transcriptionRunning: Bool,
                                     transcriptionFinalizing: Bool) -> Bool {
        !isStarting && !isRecording && !isFinalizing && !transcriptionRunning && !transcriptionFinalizing
    }
}

enum DictationHistorySaveGate {
    static func shouldSave(text: String, lastSavedText: String?, enabled: Bool) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return enabled && !normalized.isEmpty && normalized != lastSavedText
    }
}
