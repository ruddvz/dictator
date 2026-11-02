import XCTest
@testable import HushKey

final class PersonalDataBackupTests: XCTestCase {
    func testBackupRoundTripsAndKeepsVersionedFormat() throws {
        let history = [DictationHistoryEntry(text: "Keep this private.", rawText: "Um, keep this private.", duration: 2.5)]
        let backup = HushKeyPersonalDataBackup(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            dictationHistory: history,
            vocabulary: ["HushKey", "Maya"],
            snippets: "email => maya@example.com",
            correctionRules: "hush key => HushKey")

        let decoded = try HushKeyPersonalDataBackup.decode(backup.encoded())

        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(decoded.format, HushKeyPersonalDataBackup.formatIdentifier)
        XCTAssertEqual(decoded.version, HushKeyPersonalDataBackup.currentVersion)
    }

    func testBackupRejectsWrongVersionMalformedRulesDuplicatesAndOversizedFiles() throws {
        let valid = HushKeyPersonalDataBackup(dictationHistory: [], vocabulary: [], snippets: "", correctionRules: "")

        var wrongVersion = valid
        wrongVersion.version += 1
        XCTAssertThrowsError(try HushKeyPersonalDataBackup.decode(try wrongVersion.encodedForTest()))

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

        let oversized = Data(repeating: 0, count: HushKeyPersonalDataBackup.maximumFileBytes + 1)
        XCTAssertThrowsError(try HushKeyPersonalDataBackup.decode(oversized))
    }

    func testMergeAddsMissingDataAndKeepsLocalConflicts() throws {
        let sharedID = UUID()
        let local = HushKeyPersonalDataBackup(
            dictationHistory: [DictationHistoryEntry(id: sharedID, text: "Edited locally.")],
            vocabulary: ["HushKey", "local term"],
            snippets: "signature => Local sign-off",
            correctionRules: "hush key => Local spelling")
        let incoming = HushKeyPersonalDataBackup(
            dictationHistory: [
                DictationHistoryEntry(id: sharedID, text: "Older backup version."),
                DictationHistoryEntry(text: "Imported dictation.")
            ],
            vocabulary: ["hushkey", "Maya"],
            snippets: "signature => Imported sign-off\nemail => maya@example.com",
            correctionRules: "hush key => HushKey\ncolour => color")

        let merged = incoming.resolved(against: local, using: .merge)
        try merged.validate()

        XCTAssertEqual(merged.dictationHistory.count, 2)
        XCTAssertTrue(merged.dictationHistory.contains { $0.id == sharedID && $0.text == "Edited locally." })
        XCTAssertEqual(merged.vocabulary, ["HushKey", "local term", "Maya"])
        XCTAssertTrue(merged.snippets.contains("signature => Local sign-off"))
        XCTAssertTrue(merged.snippets.contains("email => maya@example.com"))
        XCTAssertTrue(merged.correctionRules.contains("hush key => Local spelling"))
        XCTAssertTrue(merged.correctionRules.contains("colour => color"))

        let replaced = incoming.resolved(against: local, using: .replace)
        XCTAssertEqual(replaced.dictationHistory, incoming.dictationHistory)
        XCTAssertEqual(replaced.vocabulary, incoming.vocabulary)
        XCTAssertEqual(replaced.snippets, incoming.snippets)
        XCTAssertEqual(replaced.correctionRules, incoming.correctionRules)
    }

    @MainActor
    func testAppModelImportsValidatedBackupAndPreservesLocalArchiveBeforeRecovery() throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let dictationURL = directory.appending(path: "hushkey-backup-import-\(suffix).json")
        let filesURL = directory.appending(path: "hushkey-backup-import-files-\(suffix).json")
        let termsBefore = UserDefaults.standard.string(forKey: "dictationTerms")
        let snippetsBefore = UserDefaults.standard.string(forKey: "dictationSnippets")
        let correctionsBefore = UserDefaults.standard.string(forKey: "dictationCorrectionRules")
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
        }

        let localEntry = DictationHistoryEntry(text: "Keep my local edit.")
        try DictationHistoryStore.save([localEntry], to: dictationURL)
        let model = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        model.dictationTerms = "local term"
        model.dictationSnippets = "signature => Local sign-off"
        model.dictationCorrectionRules = "hush key => Local spelling"

        let backup = HushKeyPersonalDataBackup(
            dictationHistory: [DictationHistoryEntry(text: "Imported dictation.")],
            vocabulary: ["local term", "HushKey"],
            snippets: "signature => Imported sign-off\nemail => user@example.com",
            correctionRules: "hush key => HushKey\ncolour => color")
        XCTAssertTrue(model.stagePersonalDataBackup(try backup.encoded()))
        model.applyPersonalDataBackup(using: .merge)

        XCTAssertEqual(model.dictationHistory.count, 2)
        XCTAssertTrue(model.dictationHistory.contains { $0.text == "Keep my local edit." })
        XCTAssertTrue(model.dictationHistory.contains { $0.text == "Imported dictation." })
        XCTAssertEqual(model.dictationTerms, "local term\nHushKey")
        XCTAssertTrue(model.dictationSnippets.contains("signature => Local sign-off"))
        XCTAssertTrue(model.dictationSnippets.contains("email => user@example.com"))
        XCTAssertTrue(model.dictationCorrectionRules.contains("hush key => Local spelling"))
        XCTAssertTrue(model.dictationCorrectionRules.contains("colour => color"))

        let damagedBytes = Data("unreadable original archive".utf8)
        try damagedBytes.write(to: dictationURL)
        let recoveryModel = AppModel(dictationHistoryURL: dictationURL, fileTranscriptionHistoryURL: filesURL)
        XCTAssertTrue(recoveryModel.dictationHistoryArchiveUnreadable)
        XCTAssertTrue(recoveryModel.stagePersonalDataBackup(try backup.encoded()))
        recoveryModel.applyPersonalDataBackup(using: .replace)

        XCTAssertFalse(recoveryModel.dictationHistoryArchiveUnreadable)
        XCTAssertEqual(recoveryModel.dictationHistory, backup.dictationHistory)
        XCTAssertEqual(DictationHistoryStore.load(from: dictationURL), backup.dictationHistory)
        XCTAssertEqual(recoveryModel.dictationTerms, "local term\nHushKey")
        XCTAssertEqual(recoveryModel.dictationSnippets, backup.snippets)
        XCTAssertEqual(recoveryModel.dictationCorrectionRules, backup.correctionRules)
        let recoveryURL = dictationURL.deletingLastPathComponent()
            .appending(path: "\(dictationURL.deletingPathExtension().lastPathComponent).corrupt-backup.json")
        XCTAssertEqual(try Data(contentsOf: recoveryURL), damagedBytes)

        XCTAssertFalse(model.stagePersonalDataBackup(Data("{}".utf8)))
        XCTAssertNil(model.pendingPersonalDataBackup)
    }
}

private extension HushKeyPersonalDataBackup {
    func encodedForTest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
