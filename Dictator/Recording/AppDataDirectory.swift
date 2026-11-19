import Foundation

/// Where Dictator keeps its local data: `~/Library/Application Support/com.ruddvz.dictator`.
enum AppDataDirectory {
    static let folderName = "com.ruddvz.dictator"
    static let previousBundleFolderName = "com.ruddvz.hushkey"
    static let legacyFolderName = "HushKey"
    /// The former shared folder may also contain data from another app. Move only these known items.
    static let legacyOwnedItems = ["dictation-history.json", "file-transcription-history.json",
                                   "meeting-notes.json", "dataset.json", "WhisperKitModels"]

    static var url: URL { url(in: isRunningTests ? testBase : .applicationSupportDirectory) }

    /// Unit tests run inside a copy of the app; they must never read or delete the user's real data.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let testBase = FileManager.default.temporaryDirectory
        .appending(path: "dictator-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    static func url(in base: URL, fileManager: FileManager = .default) -> URL {
        let directory = base.appending(path: folderName, directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        migratePriorBundleContents(in: base, to: directory, fileManager: fileManager)
        migrateLegacyItems(in: base, to: directory, fileManager: fileManager)
        return directory
    }

    /// The previous bundle-ID folder belonged to this app. Move its contents individually so a
    /// collision never replaces newer Dictator data and any skipped source remains recoverable.
    static func migratePriorBundleContents(in base: URL, to directory: URL, fileManager: FileManager = .default) {
        let previous = base.appending(path: previousBundleFolderName, directoryHint: .isDirectory)
        moveItems(in: previous, to: directory, names: childNames(in: previous, fileManager: fileManager),
                  fileManager: fileManager)
    }

    /// The old shared folder may belong to another app, so move only known Dictator-owned items.
    static func migrateLegacyItems(in base: URL, to directory: URL, fileManager: FileManager = .default) {
        let legacy = base.appending(path: legacyFolderName, directoryHint: .isDirectory)
        moveItems(in: legacy, to: directory, names: legacyOwnedItems, fileManager: fileManager)
    }

    private static func childNames(in directory: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private static func moveItems(in sourceDirectory: URL, to destinationDirectory: URL,
                                  names: [String], fileManager: FileManager) {
        for name in names {
            let source = sourceDirectory.appending(path: name)
            let destination = destinationDirectory.appending(path: name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: source, to: destination)
        }
    }
}
