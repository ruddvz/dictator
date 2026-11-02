import Foundation

enum JSONArchiveLoad<Value> {
    case missing
    case loaded(Value)
    case unreadable(recoveryCopyURL: URL?)
}

enum LocalJSONArchiveError: LocalizedError {
    case unreadable(recoveryCopyURL: URL?)

    var errorDescription: String? {
        switch self {
        case .unreadable(let recoveryCopyURL):
            if let recoveryCopyURL {
                return "The saved archive could not be read. HushKey kept a recovery copy at \(recoveryCopyURL.path). Remove the unreadable archive before saving new history."
            }
            return "The saved archive could not be read. HushKey left it in place and could not create a recovery copy. Remove the unreadable archive before saving new history."
        }
    }
}

enum LocalJSONArchive {
    private static let fileManager = FileManager.default

    static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> JSONArchiveLoad<Value> {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(recoveryCopyURL: preserveCopy(of: url))
        }
        do {
            return .loaded(try JSONDecoder().decode(type, from: data))
        } catch {
            return .unreadable(recoveryCopyURL: preserveCopy(of: url, matching: data))
        }
    }

    static func save<Value: Codable, Existing: Decodable>(
        _ value: Value,
        protectingExistingAs existingType: Existing.Type,
        to url: URL
    ) throws {
        switch load(existingType, from: url) {
        case .missing, .loaded:
            break
        case .unreadable(let recoveryCopyURL):
            throw LocalJSONArchiveError.unreadable(recoveryCopyURL: recoveryCopyURL)
        }
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func preserveCopy(of url: URL, matching originalData: Data? = nil) -> URL? {
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let base = ext.isEmpty ? "\(stem).corrupt-backup" : "\(stem).corrupt-backup.\(ext)"
        let baseURL = directory.appending(path: base)
        if fileManager.fileExists(atPath: baseURL.path) {
            if let originalData, let savedData = try? Data(contentsOf: baseURL), savedData == originalData {
                return baseURL
            }
            let versioned = ext.isEmpty
                ? "\(stem).corrupt-backup-\(UUID().uuidString)"
                : "\(stem).corrupt-backup-\(UUID().uuidString).\(ext)"
            let backupURL = directory.appending(path: versioned)
            do {
                try fileManager.copyItem(at: url, to: backupURL)
                return backupURL
            } catch {
                return nil
            }
        }
        do {
            try fileManager.copyItem(at: url, to: baseURL)
            return baseURL
        } catch {
            return nil
        }
    }
}
