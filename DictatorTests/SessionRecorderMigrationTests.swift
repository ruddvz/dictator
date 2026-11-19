import XCTest
@testable import Dictator

final class SessionRecorderMigrationTests: XCTestCase {
    func testMovesOnlyRecognizedLegacySessions() throws {
        let fm = FileManager.default
        let documents = fm.temporaryDirectory.appending(path: "dictator-sessions-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: documents) }
        let oldRoot = documents.appending(path: "HushKey/Sessions")
        let session = oldRoot.appending(path: "take-1")
        let unrelated = oldRoot.appending(path: "other-app-data")
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("time,x,y,z".utf8).write(to: session.appending(path: "motion.csv"))
        try Data("start,end,kind,label,confidence".utf8).write(to: session.appending(path: "events.csv"))
        let metadata: [String: Any] = ["condition": "Silent mouthing", "motionSamples": 2,
                                       "events": 1, "startedAt": "2026-11-20T00:00:00Z"]
        try JSONSerialization.data(withJSONObject: metadata).write(to: session.appending(path: "meta.json"))
        try Data("keep".utf8).write(to: unrelated.appending(path: "notes.txt"))

        let currentRoot = SessionRecorder.root(in: documents, fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: currentRoot.appending(path: "take-1/motion.csv").path))
        XCTAssertFalse(fm.fileExists(atPath: session.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.appending(path: "notes.txt").path))
    }

    func testDoesNotOverwriteAnExistingSession() throws {
        let fm = FileManager.default
        let documents = fm.temporaryDirectory.appending(path: "dictator-sessions-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: documents) }
        let legacy = documents.appending(path: "HushKey/Sessions/take-1")
        let current = documents.appending(path: "Dictator/Sessions/take-1")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try fm.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: current.appending(path: "motion.csv"))
        try Data("old".utf8).write(to: legacy.appending(path: "motion.csv"))
        try Data("events".utf8).write(to: legacy.appending(path: "events.csv"))
        let metadata: [String: Any] = ["condition": "Whisper", "motionSamples": 2,
                                       "events": 1, "startedAt": "2026-11-20T00:00:00Z"]
        try JSONSerialization.data(withJSONObject: metadata).write(to: legacy.appending(path: "meta.json"))

        _ = SessionRecorder.root(in: documents, fileManager: fm)

        XCTAssertEqual(try String(contentsOf: current.appending(path: "motion.csv"), encoding: .utf8), "new")
        XCTAssertTrue(fm.fileExists(atPath: legacy.appending(path: "motion.csv").path))
    }
}
