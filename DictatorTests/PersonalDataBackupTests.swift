import XCTest
@testable import Dictator

final class PersonalDataBackupTests: XCTestCase {
    func testBackupRoundTripsAndKeepsVersionedFormat() throws {
        let history = [DictationHistoryEntry(text: "Keep this private.", rawText: "Um, keep this private.", duration: 2.5)]
        let style = WritingStylePreset(name: "Friendly", instructions: "Keep it warm.")
        let profile = DictationAppProfile(appName: "Slack", bundleIdentifier: "com.example.slack",
                                          mode: .message, vocabulary: "Dictator, project Redwood",
                                          languageIdentifier: "fr-CA", snippets: "signoff => Merci",
                                          correctionRules: "dictater => Dictator", cleansFillers: true,
                                          writingStylePresetID: style.id)
        let backup = DictatorPersonalDataBackup(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            dictationHistory: history,
            vocabulary: ["Dictator", "Maya"],
            snippets: "email => maya@example.com",
            correctionRules: "dictater => Dictator",
            writingStyles: [style], appProfiles: [profile])

        let decoded = try DictatorPersonalDataBackup.decode(backup.encoded())

        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(decoded.format, DictatorPersonalDataBackup.formatIdentifier)
        XCTAssertEqual(decoded.version, DictatorPersonalDataBackup.currentVersion)
        XCTAssertEqual(decoded.appProfiles, [profile])
        XCTAssertTrue(decoded.summary.contains("1 app profile"))
    }

    func testBackupRejectsWrongVersionMalformedRulesDuplicatesAndOversizedFiles() throws {
        let valid = DictatorPersonalDataBackup(dictationHistory: [], vocabulary: [], snippets: "", correctionRules: "")

        var wrongVersion = valid
        wrongVersion.version += 1
        XCTAssertThrowsError(try DictatorPersonalDataBackup.decode(try wrongVersion.encodedForTest()))

        var malformedRules = valid
        malformedRules.snippets = "broken rule"
        XCTAssertThrowsError(try malformedRules.encoded())

        let duplicateID = UUID()
        var duplicateHistory = valid
        duplicateHistory.dictationHistory = [
            DictationHistoryEntry(id: duplicateID, text: "First."),
            DictationHistoryEntry(id: duplicateID, text: "Second.")
        ]
        XCTAssertThrowsError(try duplicateHistory.encoded())

        var duplicateStyles = valid
        let sharedStyleID = UUID()
        duplicateStyles.writingStyles = [
            WritingStylePreset(id: sharedStyleID, name: "Warm", instructions: "Keep it warm."),
            WritingStylePreset(id: sharedStyleID, name: "Brief", instructions: "Keep it brief.")
        ]
        XCTAssertThrowsError(try duplicateStyles.encoded())

        var invalidProfiles = valid
        invalidProfiles.appProfiles = [
            DictationAppProfile(appName: "Slack", bundleIdentifier: "com.example.slack",
                                mode: .automatic, vocabulary: "Dictator")
        ]
        XCTAssertThrowsError(try invalidProfiles.encoded())
        invalidProfiles.appProfiles = [
            DictationAppProfile(appName: "Slack", bundleIdentifier: "invalid",
                                mode: .message, vocabulary: "Dictator")
        ]
        XCTAssertThrowsError(try invalidProfiles.encoded())
        invalidProfiles.appProfiles = [
            DictationAppProfile(appName: "Slack", bundleIdentifier: "com.example.slack",
                                mode: .message, vocabulary: "Dictator", snippets: "broken")
        ]
        XCTAssertThrowsError(try invalidProfiles.encoded())
        invalidProfiles.appProfiles = [
            DictationAppProfile(appName: "Slack", bundleIdentifier: "com.example.slack",
                                mode: .message, vocabulary: "Dictator", writingStylePresetID: UUID())
        ]
        XCTAssertThrowsError(try invalidProfiles.encoded())

        invalidProfiles.appProfiles = (0..<DictatorPersonalDataBackup.maximumAppProfiles + 1).map { index in
            DictationAppProfile(appName: "App \(index)", bundleIdentifier: "com.example.app\(index)",
                                mode: .natural, vocabulary: "")
        }
        XCTAssertThrowsError(try invalidProfiles.encoded())

        duplicateStyles.writingStyles = [
            WritingStylePreset(name: "Warm", instructions: "Keep it warm."),
            WritingStylePreset(name: "wárm", instructions: "Keep it brief.")
        ]
        XCTAssertThrowsError(try duplicateStyles.encoded())

        let oversized = Data(repeating: 0, count: DictatorPersonalDataBackup.maximumFileBytes + 1)
        XCTAssertThrowsError(try DictatorPersonalDataBackup.decode(oversized))
    }

    func testVersionOneBackupStillImportsWithoutWritingStyles() throws {
        let data = Data(#"{"format":"com.ruddvz.dictator.personal-data","version":1,"exportedAt":0,"dictationHistory":[],"vocabulary":[],"snippets":"","correctionRules":""}"#.utf8)

        let backup = try DictatorPersonalDataBackup.decode(data)

        XCTAssertEqual(backup.version, 1)
        XCTAssertTrue(backup.writingStyles.isEmpty)

        let localStyle = WritingStylePreset(name: "Local", instructions: "Keep my style.")
        let localProfile = DictationAppProfile(appName: "Local app", bundleIdentifier: "com.example.local",
                                               mode: .natural, vocabulary: "Local", writingStylePresetID: localStyle.id)
        let current = DictatorPersonalDataBackup(
            dictationHistory: [], vocabulary: [], snippets: "", correctionRules: "",
            writingStyles: [localStyle], appProfiles: [localProfile])
        let replaced = backup.resolved(against: current, using: .replace)
        XCTAssertEqual(replaced.writingStyles, [localStyle])
        XCTAssertEqual(replaced.appProfiles, [localProfile])
    }

    func testVersionTwoReplaceRestoresStylesAndPreservesLocalProfiles() throws {
        let localStyle = WritingStylePreset(name: "Local", instructions: "Keep my local style.")
        let importedStyle = WritingStylePreset(name: "Imported", instructions: "Use the imported style.")
        let localProfile = DictationAppProfile(appName: "Editor", bundleIdentifier: "com.example.editor",
                                               mode: .code, vocabulary: "Local term")
        var versionTwo = DictatorPersonalDataBackup(dictationHistory: [], vocabulary: [], snippets: "",
                                                   correctionRules: "", writingStyles: [importedStyle])
        versionTwo.version = 2
        let decoded = try DictatorPersonalDataBackup.decode(versionTwo.encodedForTest())
        let current = DictatorPersonalDataBackup(dictationHistory: [], vocabulary: [], snippets: "",
                                                correctionRules: "", writingStyles: [localStyle],
                                                appProfiles: [localProfile])

        let replaced = decoded.resolved(against: current, using: .replace)

        XCTAssertEqual(replaced.writingStyles, [importedStyle])
        XCTAssertEqual(replaced.appProfiles, [localProfile])
    }

    func testMergeAddsMissingDataAndKeepsLocalConflicts() throws {
        let sharedID = UUID()
        let sharedStyleID = UUID()
        let conflictingImportedStyle = WritingStylePreset(name: "Warm", instructions: "Imported warm style.")
        let localProfile = DictationAppProfile(appName: "Chat", bundleIdentifier: "com.example.chat",
                                               mode: .message, vocabulary: "Local", writingStylePresetID: sharedStyleID)
        let importedConflict = DictationAppProfile(appName: "Different label", bundleIdentifier: "COM.EXAMPLE.CHAT",
                                                   mode: .code, vocabulary: "Incoming")
        let importedEditor = DictationAppProfile(appName: "Editor", bundleIdentifier: "com.example.editor",
                                                 mode: .code, vocabulary: "Dictator",
                                                 writingStylePresetID: conflictingImportedStyle.id)
        let local = DictatorPersonalDataBackup(
            dictationHistory: [DictationHistoryEntry(id: sharedID, text: "Edited locally.")],
            vocabulary: ["Dictator", "local term"],
            snippets: "signature => Local sign-off",
            correctionRules: "hush key => Local spelling",
            writingStyles: [WritingStylePreset(id: sharedStyleID, name: "Warm", instructions: "Local style.")],
            appProfiles: [localProfile])
        let incoming = DictatorPersonalDataBackup(
            dictationHistory: [
                DictationHistoryEntry(id: sharedID, text: "Older backup version."),
                DictationHistoryEntry(text: "Imported dictation.")
            ],
            vocabulary: ["dictator", "Maya"],
            snippets: "signature => Imported sign-off\nemail => maya@example.com",
            correctionRules: "dictater => Dictator\ncolour => color",
            writingStyles: [
                conflictingImportedStyle,
                WritingStylePreset(name: "Technical", instructions: "Keep the technical detail.")
            ], appProfiles: [importedConflict, importedEditor])

        let merged = incoming.resolved(against: local, using: .merge)
        try merged.validate()

        XCTAssertEqual(merged.dictationHistory.count, 2)
        XCTAssertTrue(merged.dictationHistory.contains { $0.id == sharedID && $0.text == "Edited locally." })
        XCTAssertEqual(merged.vocabulary, ["Dictator", "local term", "Maya"])
        XCTAssertTrue(merged.snippets.contains("signature => Local sign-off"))
        XCTAssertTrue(merged.snippets.contains("email => maya@example.com"))
        XCTAssertTrue(merged.correctionRules.contains("hush key => Local spelling"))
        XCTAssertTrue(merged.correctionRules.contains("colour => color"))
        XCTAssertEqual(merged.writingStyles, [local.writingStyles[0], incoming.writingStyles[1]])
        XCTAssertEqual(merged.appProfiles.count, 2)
        XCTAssertEqual(merged.appProfiles.first(where: { $0.bundleIdentifier.lowercased() == "com.example.chat" }), localProfile)
        XCTAssertEqual(merged.appProfiles.first(where: { $0.bundleIdentifier == "com.example.editor" })?.writingStylePresetID,
                       sharedStyleID)

        let replaced = incoming.resolved(against: local, using: .replace)
        XCTAssertEqual(replaced.dictationHistory, incoming.dictationHistory)
        XCTAssertEqual(replaced.vocabulary, incoming.vocabulary)
        XCTAssertEqual(replaced.snippets, incoming.snippets)
        XCTAssertEqual(replaced.correctionRules, incoming.correctionRules)
        XCTAssertEqual(replaced.writingStyles, incoming.writingStyles)
        XCTAssertEqual(replaced.appProfiles, incoming.appProfiles)
    }

    func testMergeRejectsWritingStyleOverflowInsteadOfDroppingBackupStyles() throws {
        let localStyles = (0..<WritingStylePreset.maximumCount).map {
            WritingStylePreset(name: "Local \($0)", instructions: "Use local style \($0).")
        }
        let local = DictatorPersonalDataBackup(
            dictationHistory: [], vocabulary: [], snippets: "", correctionRules: "",
            writingStyles: localStyles)
        let importedStyle = WritingStylePreset(name: "Imported", instructions: "Keep the imported style.")
        let incoming = DictatorPersonalDataBackup(
            dictationHistory: [], vocabulary: [], snippets: "", correctionRules: "",
            writingStyles: [importedStyle])

        let merged = incoming.resolved(against: local, using: .merge)

        XCTAssertEqual(merged.writingStyles.count, WritingStylePreset.maximumCount + 1)
        XCTAssertTrue(merged.writingStyles.contains(importedStyle))
        XCTAssertThrowsError(try merged.validate()) { error in
            XCTAssertTrue(error.localizedDescription.contains("more writing styles"))
        }
    }

    @MainActor
    func testReplaceBackupPersistsAppProfilesAndTheirStylesAcrossRelaunch() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "dictator-backup-profiles-\(suffix).json")
        let filesURL = directory.appending(path: "dictator-backup-profiles-files-\(suffix).json")
        let defaults = UserDefaults.standard
        let priorProfileData = defaults.object(forKey: "dictationAppProfiles")
        let priorStyleData = defaults.object(forKey: WritingStylePresetStore.preferenceKey)
        let priorSaveHistory = defaults.object(forKey: "saveDictationHistory")
        defer {
            try? FileManager.default.removeItem(at: dictationURL)
            try? FileManager.default.removeItem(at: filesURL)
            if let priorProfileData { defaults.set(priorProfileData, forKey: "dictationAppProfiles") }
            else { defaults.removeObject(forKey: "dictationAppProfiles") }
            if let priorStyleData { defaults.set(priorStyleData, forKey: WritingStylePresetStore.preferenceKey) }
            else { defaults.removeObject(forKey: WritingStylePresetStore.preferenceKey) }
            if let priorSaveHistory { defaults.set(priorSaveHistory, forKey: "saveDictationHistory") }
            else { defaults.removeObject(forKey: "saveDictationHistory") }
        }

        let localStyle = WritingStylePreset(name: "Local", instructions: "Keep it local.")
        let localProfile = DictationAppProfile(appName: "Local app", bundleIdentifier: "com.example.local",
                                               mode: .natural, vocabulary: "Local")
        defaults.set(try JSONEncoder().encode([localProfile]), forKey: "dictationAppProfiles")
        defaults.set(try JSONEncoder().encode([localStyle]), forKey: WritingStylePresetStore.preferenceKey)
        defaults.set(false, forKey: "saveDictationHistory")

        let importedStyle = WritingStylePreset(name: "Technical", instructions: "Keep the detail.")
        let importedProfile = DictationAppProfile(appName: "Editor", bundleIdentifier: "com.example.editor",
                                                  mode: .code, vocabulary: "Dictator",
                                                  writingStylePresetID: importedStyle.id)
        let backup = DictatorPersonalDataBackup(dictationHistory: [], vocabulary: [], snippets: "",
                                               correctionRules: "", writingStyles: [importedStyle],
                                               appProfiles: [importedProfile])
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))

        model.applyPersonalDataBackup(using: .replace)

        XCTAssertEqual(model.dictationAppProfiles, [importedProfile])
        XCTAssertEqual(model.writingStylePresets, [importedStyle])
        let persistedProfiles = try JSONDecoder().decode([DictationAppProfile].self,
                                                         from: try XCTUnwrap(defaults.data(forKey: "dictationAppProfiles")))
        XCTAssertEqual(persistedProfiles, [importedProfile])
        let relaunchedModel = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        XCTAssertEqual(relaunchedModel.dictationAppProfiles, [importedProfile])
        XCTAssertEqual(relaunchedModel.writingStylePresets, [importedStyle])
    }

    @MainActor
    func testReplacePersonalBackupPreservesOpenTranscriptAcrossRelaunch() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "dictator-backup-replace-draft-\(suffix).json")
        let filesURL = directory.appending(path: "dictator-backup-replace-draft-files-\(suffix).json")
        let saveHistoryBefore = UserDefaults.standard.object(forKey: "saveDictationHistory")
        defer {
            try? FileManager.default.removeItem(at: dictationURL)
            try? FileManager.default.removeItem(at: filesURL)
            if let saveHistoryBefore { UserDefaults.standard.set(saveHistoryBefore, forKey: "saveDictationHistory") }
            else { UserDefaults.standard.removeObject(forKey: "saveDictationHistory") }
        }
        UserDefaults.standard.set(true, forKey: "saveDictationHistory")

        let importedEntry = DictationHistoryEntry(text: "From the backup.")
        let backup = DictatorPersonalDataBackup(dictationHistory: [importedEntry], vocabulary: [],
                                               snippets: "", correctionRules: "")
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        model.transcriber.replaceText("Unsaved open transcript.")
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))

        model.applyPersonalDataBackup(using: .replace)

        XCTAssertNil(model.pendingPersonalDataBackup)
        XCTAssertEqual(model.dictationHistory.map(\.text), ["Unsaved open transcript.", "From the backup."])
        XCTAssertEqual(model.lastSavedDictationText, "Unsaved open transcript.")
        XCTAssertTrue(model.dataMessage?.contains("open transcript was kept in history") == true)

        let relaunchedModel = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        XCTAssertEqual(relaunchedModel.dictationHistory.map(\.text), ["Unsaved open transcript.", "From the backup."])
    }

    @MainActor
    func testReplacePersonalBackupKeepsPendingWhenHistoryIsFullAndDraftCannotFit() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "dictator-backup-full-\(suffix).json")
        let filesURL = directory.appending(path: "dictator-backup-full-files-\(suffix).json")
        let saveHistoryBefore = UserDefaults.standard.object(forKey: "saveDictationHistory")
        defer {
            try? FileManager.default.removeItem(at: dictationURL)
            try? FileManager.default.removeItem(at: filesURL)
            if let saveHistoryBefore { UserDefaults.standard.set(saveHistoryBefore, forKey: "saveDictationHistory") }
            else { UserDefaults.standard.removeObject(forKey: "saveDictationHistory") }
        }
        UserDefaults.standard.set(true, forKey: "saveDictationHistory")

        let entries = (0..<DictatorPersonalDataBackup.maximumHistoryEntries).map {
            DictationHistoryEntry(text: "Backup transcript \($0).")
        }
        let backup = DictatorPersonalDataBackup(dictationHistory: entries, vocabulary: [],
                                               snippets: "", correctionRules: "")
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        model.transcriber.replaceText("Keep this open draft.")
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))

        model.applyPersonalDataBackup(using: .replace)

        XCTAssertNotNil(model.pendingPersonalDataBackup)
        XCTAssertTrue(model.dataMessage?.contains("already has 50 dictations") == true)
        XCTAssertEqual(model.dictationHistory, [])
        XCTAssertFalse(DictationHistoryStore.containsFile(at: dictationURL))
    }

    @MainActor
    func testReplacePersonalBackupDoesNotPersistOpenDraftWhenHistorySavingIsOff() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "dictator-backup-private-draft-\(suffix).json")
        let filesURL = directory.appending(path: "dictator-backup-private-draft-files-\(suffix).json")
        let saveHistoryBefore = UserDefaults.standard.object(forKey: "saveDictationHistory")
        defer {
            try? FileManager.default.removeItem(at: dictationURL)
            try? FileManager.default.removeItem(at: filesURL)
            if let saveHistoryBefore { UserDefaults.standard.set(saveHistoryBefore, forKey: "saveDictationHistory") }
            else { UserDefaults.standard.removeObject(forKey: "saveDictationHistory") }
        }
        UserDefaults.standard.set(false, forKey: "saveDictationHistory")

        let backup = DictatorPersonalDataBackup(dictationHistory: [DictationHistoryEntry(text: "From backup.")],
                                               vocabulary: [], snippets: "", correctionRules: "")
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        model.transcriber.replaceText("Private open draft.")
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))

        model.applyPersonalDataBackup(using: .replace)

        XCTAssertEqual(model.transcriber.text, "Private open draft.")
        XCTAssertNil(model.lastSavedDictationText)
        XCTAssertEqual(model.dictationHistory.map(\.text), ["From backup."])
        XCTAssertTrue(model.dataMessage?.contains("transcript history is off") == true)
    }

    @MainActor
    func testAppModelImportsValidatedBackupAndPreservesLocalArchiveBeforeRecovery() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "dictator-backup-import-\(suffix).json")
        let filesURL = directory.appending(path: "dictator-backup-import-files-\(suffix).json")
        let termsBefore = UserDefaults.standard.string(forKey: "dictationTerms")
        let snippetsBefore = UserDefaults.standard.string(forKey: "dictationSnippets")
        let correctionsBefore = UserDefaults.standard.string(forKey: "dictationCorrectionRules")
        let writingStylesBefore = UserDefaults.standard.data(forKey: WritingStylePresetStore.preferenceKey)
        defer {
            try? FileManager.default.removeItem(at: dictationURL)
            try? FileManager.default.removeItem(at: filesURL)
            try? FileManager.default.removeItem(at: dictationURL.deletingLastPathComponent()
                .appending(path: "\(dictationURL.deletingPathExtension().lastPathComponent).corrupt-backup.json"))
            if let termsBefore { UserDefaults.standard.set(termsBefore, forKey: "dictationTerms") }
            else { UserDefaults.standard.removeObject(forKey: "dictationTerms") }
            if let snippetsBefore { UserDefaults.standard.set(snippetsBefore, forKey: "dictationSnippets") }
            else { UserDefaults.standard.removeObject(forKey: "dictationSnippets") }
            if let correctionsBefore { UserDefaults.standard.set(correctionsBefore, forKey: "dictationCorrectionRules") }
            else { UserDefaults.standard.removeObject(forKey: "dictationCorrectionRules") }
            if let writingStylesBefore { UserDefaults.standard.set(writingStylesBefore, forKey: WritingStylePresetStore.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: WritingStylePresetStore.preferenceKey) }
        }

        let localEntry = DictationHistoryEntry(text: "Keep my local edit.")
        try DictationHistoryStore.save([localEntry], to: dictationURL)
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        model.dictationTerms = "local term"
        model.dictationSnippets = "signature => Local sign-off"
        model.dictationCorrectionRules = "hush key => Local spelling"
        let localStyle = WritingStylePreset(name: "Local", instructions: "Keep my local style.")
        try model.saveWritingStylePresets([localStyle])

        let importedStyle = WritingStylePreset(name: "Imported", instructions: "Keep it concise.")
        let backup = DictatorPersonalDataBackup(
            dictationHistory: [DictationHistoryEntry(text: "Imported dictation.")],
            vocabulary: ["local term", "Dictator"],
            snippets: "signature => Imported sign-off\nemail => user@example.com",
            correctionRules: "dictater => Dictator\ncolour => color",
            writingStyles: [importedStyle])
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))
        model.applyPersonalDataBackup(using: .merge)

        XCTAssertEqual(model.dictationHistory.count, 2)
        XCTAssertTrue(model.dictationHistory.contains { $0.text == "Keep my local edit." })
        XCTAssertTrue(model.dictationHistory.contains { $0.text == "Imported dictation." })
        XCTAssertEqual(model.dictationTerms, "local term\nDictator")
        XCTAssertTrue(model.dictationSnippets.contains("signature => Local sign-off"))
        XCTAssertTrue(model.dictationSnippets.contains("email => user@example.com"))
        XCTAssertTrue(model.dictationCorrectionRules.contains("hush key => Local spelling"))
        XCTAssertTrue(model.dictationCorrectionRules.contains("colour => color"))
        XCTAssertEqual(model.writingStylePresets, [localStyle, importedStyle])

        let damagedBytes = Data("unreadable original archive".utf8)
        try damagedBytes.write(to: dictationURL)
        let recoveryModel = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        XCTAssertTrue(recoveryModel.dictationHistoryArchiveUnreadable)
        XCTAssertTrue(recoveryModel.stagePersonalDataBackup(try backup.encoded()))
        recoveryModel.applyPersonalDataBackup(using: .replace)

        XCTAssertFalse(recoveryModel.dictationHistoryArchiveUnreadable)
        XCTAssertEqual(recoveryModel.dictationHistory, backup.dictationHistory)
        XCTAssertEqual(DictationHistoryStore.load(from: dictationURL), backup.dictationHistory)
        XCTAssertEqual(recoveryModel.dictationTerms, "local term\nDictator")
        XCTAssertEqual(recoveryModel.dictationSnippets, backup.snippets)
        XCTAssertEqual(recoveryModel.dictationCorrectionRules, backup.correctionRules)
        XCTAssertEqual(recoveryModel.writingStylePresets, [importedStyle])
        let recoveryURL = dictationURL.deletingLastPathComponent()
            .appending(path: "\(dictationURL.deletingPathExtension().lastPathComponent).corrupt-backup.json")
        XCTAssertEqual(try Data(contentsOf: recoveryURL), damagedBytes)

        XCTAssertFalse(model.stagePersonalDataBackup(Data("{}".utf8)))
        XCTAssertNil(model.pendingPersonalDataBackup)
    }
}

private extension DictatorPersonalDataBackup {
    func encodedForTest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
