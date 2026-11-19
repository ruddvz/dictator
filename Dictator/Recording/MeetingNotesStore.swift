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

struct MeetingNotesDraft: Codable, Identifiable, Equatable {
    var id: UUID
    var startedAt: Date
    var duration: TimeInterval
    var audioSource: MeetingAudioSource
    var transcript: String

    init(id: UUID = UUID(), startedAt: Date, duration: TimeInterval,
         audioSource: MeetingAudioSource, transcript: String) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.audioSource = audioSource
        self.transcript = transcript
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
        switch loadState(from: url) {
        case .loaded(let notes): notes
        case .missing, .unreadable: nil
        }
    }

    static func loadState(from url: URL) -> JSONArchiveLoad<[MeetingNote]> {
        LocalJSONArchive.load([MeetingNote].self, from: url)
    }

    static func save(_ notes: [MeetingNote]) throws {
        try save(notes, to: url)
    }

    static func save(_ notes: [MeetingNote], to url: URL) throws {
        try LocalJSONArchive.save(notes, protectingExistingAs: [MeetingNote].self, to: url)
    }

    static func delete(at url: URL = url) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum MeetingNotesDraftStore {
    private static let fileManager = FileManager.default

    static var url: URL {
        AppDataDirectory.url.appending(path: "meeting-notes-active-draft.json")
    }

    static func loadState(from url: URL = url) -> JSONArchiveLoad<MeetingNotesDraft> {
        LocalJSONArchive.load(MeetingNotesDraft.self, from: url)
    }

    static func save(_ draft: MeetingNotesDraft, to url: URL = url) throws {
        try LocalJSONArchive.save(draft, protectingExistingAs: MeetingNotesDraft.self, to: url)
    }

    static func delete(at url: URL = url) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
