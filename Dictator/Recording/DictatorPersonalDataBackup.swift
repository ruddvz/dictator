import Foundation

enum PersonalDataImportStrategy: Equatable {
    case merge
    case replace
}

struct DictatorPersonalDataBackup: Codable, Equatable {
    static let formatIdentifier = "com.ruddvz.dictator.personal-data"
    static let currentVersion = 3
    static let maximumFileBytes = 10 * 1_024 * 1_024
    static let maximumHistoryEntries = 50
    static let maximumVocabularyTerms = 500
    static let maximumDefinitionLines = 500
    static let maximumAppProfiles = 100

    var format: String
    var version: Int
    var exportedAt: Date
    var dictationHistory: [DictationHistoryEntry]
    var vocabulary: [String]
    var snippets: String
    var correctionRules: String
    var writingStyles: [WritingStylePreset]
    var appProfiles: [DictationAppProfile]

    init(exportedAt: Date = Date(), dictationHistory: [DictationHistoryEntry], vocabulary: [String],
         snippets: String, correctionRules: String, writingStyles: [WritingStylePreset] = [],
         appProfiles: [DictationAppProfile] = []) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.dictationHistory = dictationHistory
        self.vocabulary = vocabulary
        self.snippets = snippets
        self.correctionRules = correctionRules
        self.writingStyles = writingStyles
        self.appProfiles = appProfiles
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, dictationHistory, vocabulary, snippets, correctionRules, writingStyles, appProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        dictationHistory = try container.decode([DictationHistoryEntry].self, forKey: .dictationHistory)
        vocabulary = try container.decode([String].self, forKey: .vocabulary)
        snippets = try container.decode(String.self, forKey: .snippets)
        correctionRules = try container.decode(String.self, forKey: .correctionRules)
        writingStyles = try container.decodeIfPresent([WritingStylePreset].self, forKey: .writingStyles) ?? []
        appProfiles = version >= 3 ? try container.decode([DictationAppProfile].self, forKey: .appProfiles) : []
    }

    static func decode(_ data: Data) throws -> DictatorPersonalDataBackup {
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
        guard (1...Self.currentVersion).contains(version) else { throw BackupError.unsupportedVersion(version) }
        guard exportedAt.timeIntervalSince1970.isFinite else { throw BackupError.invalidExportDate }
        guard dictationHistory.count <= Self.maximumHistoryEntries else { throw BackupError.tooManyHistoryEntries }
        guard Set(dictationHistory.map(\.id)).count == dictationHistory.count else { throw BackupError.duplicateHistoryEntry }
        for entry in dictationHistory {
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.text.utf8.count <= 300_000,
                  (entry.rawText?.utf8.count ?? 0) <= 300_000,
                  (entry.cleanedText?.utf8.count ?? 0) <= 300_000,
                  (entry.appName?.utf8.count ?? 0) <= 1_000,
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

        guard writingStyles.count <= WritingStylePreset.maximumCount else { throw BackupError.tooManyWritingStyles }
        var seenStyleIDs = Set<UUID>()
        var seenStyleNames = Set<String>()
        for style in writingStyles {
            let nameKey = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenStyleIDs.insert(style.id).inserted,
                  seenStyleNames.insert(nameKey).inserted,
                  !style.name.contains(where: \.isNewline),
                  WritingStylePreset.validationIssue(name: style.name, instructions: style.instructions) == nil else {
                throw BackupError.invalidWritingStyles
            }
        }

        if version >= 3 {
            guard appProfiles.count <= Self.maximumAppProfiles else { throw BackupError.tooManyAppProfiles }
            let validStyleIDs = Set(writingStyles.map(\.id))
            var seenBundleIdentifiers = Set<String>()
            for profile in appProfiles {
                let key = DictationAppProfile.normalizedBundleIdentifier(profile.bundleIdentifier)
                guard DictationAppProfile.isValidForBackup(profile, writingStyleIDs: validStyleIDs),
                      seenBundleIdentifiers.insert(key).inserted else {
                    throw BackupError.invalidAppProfiles
                }
            }
        }
    }

    func resolved(against current: DictatorPersonalDataBackup,
                  using strategy: PersonalDataImportStrategy) -> DictatorPersonalDataBackup {
        if strategy == .replace {
            let resolvedStyles = version == 1 ? current.writingStyles : writingStyles
            let resolvedProfiles = version < 3 ? current.appProfiles : appProfiles
            return DictatorPersonalDataBackup(
                exportedAt: Date(), dictationHistory: dictationHistory, vocabulary: vocabulary,
                snippets: snippets, correctionRules: correctionRules, writingStyles: resolvedStyles,
                appProfiles: Self.clearingMissingStyleReferences(in: resolvedProfiles, validStyleIDs: Set(resolvedStyles.map(\.id))))
        }
        var historyByID: [UUID: DictationHistoryEntry] = [:]
        for entry in current.dictationHistory { historyByID[entry.id] = entry }
        for entry in dictationHistory where historyByID[entry.id] == nil {
            historyByID[entry.id] = entry
        }
        let mergedHistory = historyByID.values.sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.maximumHistoryEntries)
        let mergedStyles = Self.mergingStyles(current.writingStyles, with: writingStyles)
        let mergedProfiles = Self.mergingProfiles(current.appProfiles, with: appProfiles,
                                                   importedStyles: writingStyles, mergedStyles: mergedStyles)
        return DictatorPersonalDataBackup(
            exportedAt: Date(),
            dictationHistory: Array(mergedHistory),
            vocabulary: DictationVocabulary.terms(from: current.vocabulary.joined(separator: "\n") + "\n" +
                                                   vocabulary.joined(separator: "\n")),
            snippets: Self.mergingDefinitions(current.snippets, with: snippets),
            correctionRules: Self.mergingDefinitions(current.correctionRules, with: correctionRules),
            writingStyles: mergedStyles,
            appProfiles: Self.clearingMissingStyleReferences(in: mergedProfiles, validStyleIDs: Set(mergedStyles.map(\.id))))
    }

    var summary: String {
        let snippetCount = DictationSnippetExpander.validation(for: snippets).validCount
        let correctionCount = DictationCorrectionRules.validation(for: correctionRules).validCount
        let profileLabel = appProfiles.count == 1 ? "1 app profile" : "\(appProfiles.count) app profiles"
        return "\(dictationHistory.count) dictations, \(vocabulary.count) vocabulary terms, \(snippetCount) snippets, \(correctionCount) correction rules, \(writingStyles.count) writing styles and \(profileLabel)."
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

    private static func mergingStyles(_ existing: [WritingStylePreset], with incoming: [WritingStylePreset]) -> [WritingStylePreset] {
        var merged = existing
        var ids = Set(existing.map(\.id))
        var names = Set(existing.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        for style in incoming {
            let name = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard ids.insert(style.id).inserted, names.insert(name).inserted else { continue }
            merged.append(style)
        }
        return merged
    }

    private static func mergingProfiles(_ existing: [DictationAppProfile], with incoming: [DictationAppProfile],
                                        importedStyles: [WritingStylePreset],
                                        mergedStyles: [WritingStylePreset]) -> [DictationAppProfile] {
        var merged = existing
        var bundleIdentifiers = Set(existing.map { DictationAppProfile.normalizedBundleIdentifier($0.bundleIdentifier) })
        let importedStyleByID = Dictionary(uniqueKeysWithValues: importedStyles.map { ($0.id, $0) })
        for profile in incoming {
            let key = DictationAppProfile.normalizedBundleIdentifier(profile.bundleIdentifier)
            guard bundleIdentifiers.insert(key).inserted else { continue }
            var imported = profile
            if let styleID = profile.writingStylePresetID,
               let sourceStyle = importedStyleByID[styleID] {
                let name = normalizedStyleName(sourceStyle.name)
                imported.writingStylePresetID = mergedStyles.first(where: { $0.id == styleID })?.id
                    ?? mergedStyles.first(where: { normalizedStyleName($0.name) == name })?.id
            }
            merged.append(imported)
        }
        return merged
    }

    private static func clearingMissingStyleReferences(in profiles: [DictationAppProfile],
                                                       validStyleIDs: Set<UUID>) -> [DictationAppProfile] {
        profiles.map { profile in
            guard let styleID = profile.writingStylePresetID, !validStyleIDs.contains(styleID) else { return profile }
            var updated = profile
            updated.writingStylePresetID = nil
            return updated
        }
    }

    private static func normalizedStyleName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
        case tooManyWritingStyles
        case invalidWritingStyles
        case tooManyAppProfiles
        case invalidAppProfiles
        case invalidDefinitions(DefinitionKind, [Int])
        case definitionEntryTooLong(DefinitionKind)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: return "This backup is larger than Dictator allows."
            case .wrongFormat: return "This JSON file is not a Dictator personal data backup."
            case .unsupportedVersion(let version): return "This backup uses an unsupported format version (\(version)). Update Dictator before importing it."
            case .invalidExportDate: return "This backup has an invalid export date."
            case .tooManyHistoryEntries: return "This backup has more dictations than Dictator can store."
            case .duplicateHistoryEntry: return "This backup contains duplicate dictation records."
            case .invalidHistoryEntry: return "This backup contains an empty or invalid dictation record."
            case .tooManyVocabularyTerms: return "This backup contains too many vocabulary terms."
            case .invalidVocabulary: return "This backup contains an empty, repeated or invalid vocabulary term."
            case .definitionsTooLarge: return "The snippet or correction rules exceed the allowed size."
            case .tooManyDefinitions: return "The backup contains too many snippet or correction rules."
            case .tooManyWritingStyles: return "The backup contains more writing styles than Dictator can store."
            case .invalidWritingStyles: return "The backup contains an invalid or duplicate writing style."
            case .tooManyAppProfiles: return "The backup contains more app profiles than Dictator can store."
            case .invalidAppProfiles: return "The backup contains an invalid or duplicate app profile."
            case .invalidDefinitions(let kind, let lines):
                let name = kind == .snippet ? "snippet" : "correction"
                return "The backup has invalid \(name) rules on line\(lines.count == 1 ? "" : "s") \(lines.map(String.init).joined(separator: ", "))."
            case .definitionEntryTooLong(let kind):
                return kind == .snippet ? "A snippet cue or expansion is too long." : "A correction cue or replacement is too long."
            }
        }
    }
}
