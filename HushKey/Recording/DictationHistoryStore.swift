import Foundation

struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var text: String
    var rawText: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), text: String, rawText: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.rawText = rawText
    }
}

enum DictationHistoryStore {
    private static let fileManager = FileManager.default

    static var url: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "HushKey", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "dictation-history.json")
    }

    static func containsFile(at url: URL = url) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    static func load() -> [DictationHistoryEntry] {
        load(from: url) ?? []
    }

    static func load(from url: URL) -> [DictationHistoryEntry]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([DictationHistoryEntry].self, from: data)
    }

    static func save(_ entries: [DictationHistoryEntry]) throws {
        try save(entries, to: url)
    }

    static func save(_ entries: [DictationHistoryEntry], to url: URL) throws {
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    static func delete(at url: URL = url) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum DictationHistorySaveGate {
    static func shouldSave(text: String, lastSavedText: String?, enabled: Bool) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return enabled && !normalized.isEmpty && normalized != lastSavedText
    }
}
