import Foundation

struct Dataset: Codable {
    var vocabulary: [String]
    var templates: [Template]

    static let starter = Dataset(vocabulary: ["yes", "no", "next", "back", "stop"], templates: [])
}

/// Persists the training set as JSON in Application Support.
enum TemplateStore {
    static var url: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "HushKey", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "dataset.json")
    }

    static func load() -> Dataset {
        load(from: url) ?? .starter
    }

    static func save(_ dataset: Dataset) {
        do {
            try save(dataset, to: url)
        } catch {
            print("HushKey: failed to save dataset: \(error)")
        }
    }

    static func load(from url: URL) -> Dataset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Dataset.self, from: data)
    }

    static func save(_ dataset: Dataset, to url: URL) throws {
        try JSONEncoder().encode(dataset).write(to: url, options: .atomic)
    }
}
