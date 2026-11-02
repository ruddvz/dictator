import Foundation

/// Where HushKey keeps its local data: `~/Library/Application Support/com.ruddvz.hushkey`.
///
/// Older builds used `…/HushKey`, which on the usual case-insensitive Mac disk is the same folder
/// as the unrelated amirrsyed/hushkey app's `…/Hushkey`. That app's uninstaller offers to delete
/// the whole folder, which would take HushKey's history with it. So HushKey now uses a folder
/// named after its bundle identifier, and moves only its own files out of the old one.
enum AppDataDirectory {
    static let folderName = "com.ruddvz.hushkey"
    static let legacyFolderName = "HushKey"
    /// Every file or folder HushKey ever wrote to the legacy folder. Nothing else is touched there.
    static let ownedItems = ["dictation-history.json", "file-transcription-history.json",
                             "meeting-notes.json", "dataset.json", "WhisperKitModels"]

    static var url: URL { url(in: isRunningTests ? testBase : .applicationSupportDirectory) }

    /// Unit tests run inside a copy of the app; they must never read or delete the user's real data.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let testBase = FileManager.default.temporaryDirectory
        .appending(path: "hushkey-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    static func url(in base: URL, fileManager: FileManager = .default) -> URL {
        let directory = base.appending(path: folderName, directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        migrateLegacyItems(in: base, to: directory, fileManager: fileManager)
        return directory
    }

    /// Moves HushKey's own items from the legacy folder; never overwrites newer data and never
    /// deletes the legacy folder, which may hold the other app's files.
    static func migrateLegacyItems(in base: URL, to directory: URL, fileManager: FileManager = .default) {
        let legacy = base.appending(path: legacyFolderName, directoryHint: .isDirectory)
        for name in ownedItems {
            let source = legacy.appending(path: name)
            let destination = directory.appending(path: name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: source, to: destination)
        }
    }
}
