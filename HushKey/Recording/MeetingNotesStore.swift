import Foundation

struct MeetingNote: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var title: String
    var transcript: String
    var summary: String
    var actionItems: String

    init(id: UUID = UUID(), createdAt: Date = Date(), duration: TimeInterval = 0,
         title: String, transcript: String, summary: String = "", actionItems: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.title = title
        self.transcript = transcript
        self.summary = summary
        self.actionItems = actionItems
    }
}

enum MeetingNotesStore {
    private static let fileManager = FileManager.default

    static var url: URL {
        AppDataDirectory.url.appending(path: "meeting-notes.json")
    }

    static func load() -> [MeetingNote] {
        load(from: url) ?? []
    }

    static func load(from url: URL) -> [MeetingNote]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([MeetingNote].self, from: data)
    }

    static func save(_ notes: [MeetingNote]) throws {
        try save(notes, to: url)
    }

    static func save(_ notes: [MeetingNote], to url: URL) throws {
        try JSONEncoder().encode(notes).write(to: url, options: .atomic)
    }

    static func delete(at url: URL = url) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
