import XCTest
@testable import HushKey

final class AppDataDirectoryTests: XCTestCase {
    func testMovesOnlyHushKeyFilesOutOfTheSharedLegacyFolder() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "hushkey-data-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appending(path: AppDataDirectory.legacyFolderName)
        try fm.createDirectory(at: legacy.appending(path: "venv"), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: legacy.appending(path: "dictation-history.json"))

        let directory = AppDataDirectory.url(in: base)

        XCTAssertEqual(directory.lastPathComponent, "com.ruddvz.hushkey")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "dictation-history.json"), encoding: .utf8), "history")
        XCTAssertFalse(fm.fileExists(atPath: legacy.appending(path: "dictation-history.json").path))
        XCTAssertTrue(fm.fileExists(atPath: legacy.appending(path: "venv").path), "the other app's files stay put")
    }

    func testNeverOverwritesNewerData() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "hushkey-data-\(UUID().uuidString)")
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
}
