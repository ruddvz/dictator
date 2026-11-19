import XCTest
@testable import Dictator

final class AppDataDirectoryTests: XCTestCase {
    func testMovesOnlyDictatorFilesOutOfTheSharedLegacyFolder() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "dictator-data-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appending(path: AppDataDirectory.legacyFolderName)
        try fm.createDirectory(at: legacy.appending(path: "venv"), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: legacy.appending(path: "dictation-history.json"))

        let directory = AppDataDirectory.url(in: base)

        XCTAssertEqual(directory.lastPathComponent, "com.ruddvz.dictator")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "dictation-history.json"), encoding: .utf8), "history")
        XCTAssertFalse(fm.fileExists(atPath: legacy.appending(path: "dictation-history.json").path))
        XCTAssertTrue(fm.fileExists(atPath: legacy.appending(path: "venv").path), "the other app's files stay put")
    }

    func testMovesPriorBundleContentsAndPreservesConflicts() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "dictator-migration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let previous = base.appending(path: AppDataDirectory.previousBundleFolderName)
        let current = base.appending(path: AppDataDirectory.folderName)
        try fm.createDirectory(at: previous.appending(path: "CleanupModels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: previous.appending(path: "CleanupModels/model.gguf"))
        try Data("old".utf8).write(to: previous.appending(path: "meeting-notes.json"))
        try Data("new".utf8).write(to: current.appending(path: "meeting-notes.json"))

        _ = AppDataDirectory.url(in: base)

        XCTAssertEqual(try String(contentsOf: current.appending(path: "CleanupModels/model.gguf"), encoding: .utf8), "model")
        XCTAssertEqual(try String(contentsOf: current.appending(path: "meeting-notes.json"), encoding: .utf8), "new")
        XCTAssertTrue(fm.fileExists(atPath: previous.appending(path: "meeting-notes.json").path))
    }

    func testNeverOverwritesNewerData() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "dictator-data-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appending(path: AppDataDirectory.legacyFolderName)
        let current = base.appending(path: AppDataDirectory.folderName)
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try fm.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appending(path: "meeting-notes.json"))
        try Data("new".utf8).write(to: current.appending(path: "meeting-notes.json"))

        _ = AppDataDirectory.url(in: base)

        XCTAssertEqual(try String(contentsOf: current.appending(path: "meeting-notes.json"), encoding: .utf8), "new")
        XCTAssertTrue(fm.fileExists(atPath: legacy.appending(path: "meeting-notes.json").path))
    }

    func testUnitTestsNeverUseTheRealDataFolder() {
        XCTAssertTrue(AppDataDirectory.isRunningTests)
        XCTAssertFalse(AppDataDirectory.url.path.contains("Application Support"), AppDataDirectory.url.path)
        XCTAssertFalse(DictationHistoryStore.url.path.contains("Application Support"))
    }
}
