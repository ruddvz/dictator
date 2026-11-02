import Foundation

enum PersonalDataImportStrategy: Equatable {
    case merge
    case replace
}

struct HushKeyPersonalDataBackup: Codable, Equatable {
    static let formatIdentifier = "com.ruddvz.hushkey.personal-data"
    static let currentVersion = 1
    static let maximumFileBytes = 10 * 1_024 * 1_024
    static let maximumHistoryEntries = 50
    static let maximumVocabularyTerms = 500
    static let maximumDefinitionLines = 500

    var format: String
    var version: Int
    var exportedAt: Date
    var dictationHistory: [DictationHistoryEntry]
    var vocabulary: [String]
    var snippets: String
    var correctionRules: String

    init(exportedAt: Date = Date(), dictationHistory: [DictationHistoryEntry], vocabulary: [String],
         snippets: String, correctionRules: String) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.dictationHistory = dictationHistory
        self.vocabulary = vocabulary
        self.snippets = snippets
        self.correctionRules = correctionRules
    }

    static func decode(_ data: Data) throws -> HushKeyPersonalDataBackup {
        guard data.count <= maximumFileBytes else { throw BackupError.fileTooLarge }
        let backup = try JSONDecoder().decode(Self.self, from: data)
        try backup.validate()
        return backup
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileBytes else { throw BackupError.fileTooLarge }
        return data
    }

    func validate() throws {
        guard format == Self.formatIdentifier else { throw BackupError.wrongFormat }
        guard version == Self.currentVersion else { throw BackupError.unsupportedVersion(version) }
        guard exportedAt.timeIntervalSince1970.isFinite else { throw BackupError.invalidExportDate }
        guard dictationHistory.count <= Self.maximumHistoryEntries else { throw BackupError.tooManyHistoryEntries }
        guard Set(dictationHistory.map(\.id)).count == dictationHistory.count else { throw BackupError.duplicateHistoryEntry }
        for entry in dictationHistory {
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.text.utf8.count <= 300_000,
                  (entry.rawText?.utf8.count ?? 0) <= 300_000,
                  entry.duration.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw BackupError.invalidHistoryEntry
            }
        }

        guard vocabulary.count <= Self.maximumVocabularyTerms else { throw BackupError.tooManyVocabularyTerms }
        var seenTerms = Set<String>()
        for term in vocabulary {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !clean.isEmpty, clean.count <= 128, !clean.contains(","), !clean.contains(where: \.isNewline),
                  seenTerms.insert(key).inserted else {
                throw BackupError.invalidVocabulary
            }
        }

        try Self.validateDefinitions(snippets, kind: .snippet)
        try Self.validateDefinitions(correctionRules, kind: .correction)
    }

    func resolved(against current: HushKeyPersonalDataBackup,
                  using strategy: PersonalDataImportStrategy) -> HushKeyPersonalDataBackup {
        guard strategy == .merge else { return self }
        var historyByID: [UUID: DictationHistoryEntry] = [:]
        for entry in current.dictationHistory { historyByID[entry.id] = entry }
        for entry in dictationHistory where historyByID[entry.id] == nil {
            historyByID[entry.id] = entry
        }
        let mergedHistory = historyByID.values.sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.maximumHistoryEntries)
        return HushKeyPersonalDataBackup(
            exportedAt: Date(),
            dictationHistory: Array(mergedHistory),
            vocabulary: DictationVocabulary.terms(from: current.vocabulary.joined(separator: "\n") + "\n" +
                                                   vocabulary.joined(separator: "\n")),
            snippets: Self.mergingDefinitions(current.snippets, with: snippets),
            correctionRules: Self.mergingDefinitions(current.correctionRules, with: correctionRules))
    }

    var summary: String {
        let snippetCount = DictationSnippetExpander.validation(for: snippets).validCount
        let correctionCount = DictationCorrectionRules.validation(for: correctionRules).validCount
        return "\(dictationHistory.count) dictations, \(vocabulary.count) vocabulary terms, \(snippetCount) snippets and \(correctionCount) correction rules."
    }

    private static func validateDefinitions(_ definitions: String, kind: DefinitionKind) throws {
        guard definitions.utf8.count <= 1_000_000 else { throw BackupError.definitionsTooLarge }
        let lineCount = definitions.split(whereSeparator: \.isNewline).count
        guard lineCount <= maximumDefinitionLines else { throw BackupError.tooManyDefinitions }
        let validation = kind == .snippet
            ? DictationSnippetExpander.validation(for: definitions)
            : DictationCorrectionRules.validation(for: definitions)
        guard validation.invalidLines.isEmpty else { throw BackupError.invalidDefinitions(kind, validation.invalidLines) }
        for line in definitions.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            let cue = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let replacement = parts.dropFirst().joined(separator: "=>").trimmingCharacters(in: .whitespacesAndNewlines)
            guard cue.count <= 120, replacement.count <= 20_000 else {
                throw BackupError.definitionEntryTooLong(kind)
            }
        }
    }

    private static func mergingDefinitions(_ existing: String, with incoming: String) -> String {
        var lines = existing.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var cues = Set(lines.compactMap { line -> String? in
            let parts = line.components(separatedBy: "=>")
            guard parts.count >= 2 else { return nil }
            let cue = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cue.isEmpty else { return nil }
            return cue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        for line in incoming.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "=>")
            guard parts.count >= 2 else { continue }
            let cue = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if cues.insert(key).inserted { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    enum DefinitionKind: Equatable {
        case snippet
        case correction
    }

    enum BackupError: LocalizedError {
        case fileTooLarge
        case wrongFormat
        case unsupportedVersion(Int)
        case invalidExportDate
        case tooManyHistoryEntries
        case duplicateHistoryEntry
        case invalidHistoryEntry
        case tooManyVocabularyTerms
        case invalidVocabulary
        case definitionsTooLarge
        case tooManyDefinitions
        case invalidDefinitions(DefinitionKind, [Int])
        case definitionEntryTooLong(DefinitionKind)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: return "This backup is larger than HushKey allows."
            case .wrongFormat: return "This JSON file is not a HushKey personal data backup."
            case .unsupportedVersion(let version): return "This backup uses an unsupported format version (\(version)). Update HushKey before importing it."
            case .invalidExportDate: return "This backup has an invalid export date."
            case .tooManyHistoryEntries: return "This backup has more dictations than HushKey can store."
            case .duplicateHistoryEntry: return "This backup contains duplicate dictation records."
            case .invalidHistoryEntry: return "This backup contains an empty or invalid dictation record."
            case .tooManyVocabularyTerms: return "This backup contains too many vocabulary terms."
            case .invalidVocabulary: return "This backup contains an empty, repeated or invalid vocabulary term."
            case .definitionsTooLarge: return "The snippet or correction rules exceed the allowed size."
            case .tooManyDefinitions: return "The backup contains too many snippet or correction rules."
            case .invalidDefinitions(let kind, let lines):
                let name = kind == .snippet ? "snippet" : "correction"
                return "The backup has invalid \(name) rules on line\(lines.count == 1 ? "" : "s") \(lines.map(String.init).joined(separator: ", "))."
            case .definitionEntryTooLong(let kind):
                return kind == .snippet ? "A snippet cue or expansion is too long." : "A correction cue or replacement is too long."
            }
        }
    }
}
