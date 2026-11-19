import Foundation

struct Dataset: Codable {
    var vocabulary: [String]
    var templates: [Template]

    static let starter = Dataset(vocabulary: ["yes", "no", "next", "back", "stop"], templates: [])
}

/// Persists the training set as JSON in Application Support.
enum TemplateStore {
    static var url: URL {
        AppDataDirectory.url.appending(path: "dataset.json")
    }

    static func loadState(from url: URL = url) -> JSONArchiveLoad<Dataset> {
        LocalJSONArchive.load(Dataset.self, from: url)
    }

    static func load(from url: URL) -> Dataset? {
        if case .loaded(let dataset) = loadState(from: url) { return dataset }
        return nil
    }

    static func save(_ dataset: Dataset, to url: URL) throws {
        try LocalJSONArchive.save(dataset, protectingExistingAs: Dataset.self, to: url)
    }

    static func delete(at url: URL = url) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
