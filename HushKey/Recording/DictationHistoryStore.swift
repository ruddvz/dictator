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
    static var url: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "HushKey", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "dictation-history.json")
    }

    static func load() -> [DictationHistoryEntry] {
        load(from: url) ?? []
    }

    static func load(from url: URL) -> [DictationHistoryEntry]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([DictationHistoryEntry].self, from: data)
    }

    static func save(_ entries: [DictationHistoryEntry]) {
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    static func save(_ entries: [DictationHistoryEntry], to url: URL) throws {
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
