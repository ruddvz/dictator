import Foundation

enum FileTranscriptionEngine: String, CaseIterable, Codable, Identifiable {
    case apple = "Apple Speech"
    case whisperKit = "WhisperKit model"

    var id: String { rawValue }
}

struct FileTranscriptionSession: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var sourceName: String
    var engine: FileTranscriptionEngine
    var languageIdentifier: String
    var modelVariant: String?
    var text: String
    var cues: [SubtitleCue]

    init(id: UUID = UUID(), createdAt: Date = Date(), sourceName: String,
         engine: FileTranscriptionEngine, languageIdentifier: String,
         modelVariant: String? = nil, text: String, cues: [SubtitleCue]) {
        self.id = id
        self.createdAt = createdAt
        self.sourceName = sourceName
        self.engine = engine
        self.languageIdentifier = languageIdentifier
        self.modelVariant = modelVariant
        self.text = text
        self.cues = cues
    }
}

enum FileTranscriptionSessionSnapshot {
    static func make(activeSessionID: UUID?, switchingTo targetSessionID: UUID? = nil,
                     sourceName: String, engine: FileTranscriptionEngine,
                     languageIdentifier: String, modelVariant: String?,
                     text: String, cues: [SubtitleCue]) -> FileTranscriptionSession? {
        guard let activeSessionID, activeSessionID != targetSessionID else { return nil }
        return FileTranscriptionSession(id: activeSessionID, sourceName: sourceName,
                                        engine: engine, languageIdentifier: languageIdentifier,
                                        modelVariant: modelVariant, text: text, cues: cues)
    }
}

enum FileTranscriptionSessionStore {
    private static let fileManager = FileManager.default

    static var url: URL {
        AppDataDirectory.url.appending(path: "file-transcription-history.json")
    }

    static func load() -> [FileTranscriptionSession] {
        load(from: url) ?? []
    }

    static func load(from url: URL) -> [FileTranscriptionSession]? {
        switch loadState(from: url) {
        case .loaded(let sessions): sessions
        case .missing, .unreadable: nil
        }
    }

    static func loadState(from url: URL) -> JSONArchiveLoad<[FileTranscriptionSession]> {
        LocalJSONArchive.load([FileTranscriptionSession].self, from: url)
    }

    static func save(_ sessions: [FileTranscriptionSession]) throws {
        try save(sessions, to: url)
    }

    static func save(_ sessions: [FileTranscriptionSession], to url: URL) throws {
        try LocalJSONArchive.save(Array(sessions.sorted { $0.createdAt > $1.createdAt }.prefix(50)),
                                  protectingExistingAs: [FileTranscriptionSession].self, to: url)
    }

    static func upserting(_ session: FileTranscriptionSession,
                          into sessions: [FileTranscriptionSession]) -> [FileTranscriptionSession] {
        var updated = sessions
        if let index = updated.firstIndex(where: { $0.id == session.id }) {
            var replacement = session
            replacement.createdAt = updated[index].createdAt
            updated[index] = replacement
        } else {
            updated.append(session)
        }
        return Array(updated.sorted { $0.createdAt > $1.createdAt }.prefix(50))
    }

    static func deleting(id: UUID, from sessions: [FileTranscriptionSession]) -> [FileTranscriptionSession] {
        sessions.filter { $0.id != id }
    }

    static func deleteAll() throws {
        try deleteAll(at: url)
    }

    static func deleteAll(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
