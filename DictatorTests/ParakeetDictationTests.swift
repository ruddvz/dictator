import DictatorParakeet
import XCTest
@testable import Dictator

final class DictationVocabularySnapperTests: XCTestCase {
    func testJoinsAWordSplitAcrossSpaces() {
        XCTAssertEqual(DictationVocabularySnapper.apply("Open dic tator and type.", terms: ["Dictator"]),
                       "Open Dictator and type.")
        XCTAssertEqual(DictationVocabularySnapper.apply("I like type script, mostly", terms: ["TypeScript"]),
                       "I like TypeScript, mostly")
    }

    func testFixesCapitalsOnlyWhenTheTermHasThem() {
        XCTAssertEqual(DictationVocabularySnapper.apply("Push it to github.", terms: ["GitHub"]), "Push it to GitHub.")
        // A lowercase term never lowercases the start of a sentence.
        XCTAssertEqual(DictationVocabularySnapper.apply("Sage is the accent.", terms: ["sage"]), "Sage is the accent.")
    }

    func testFixesACapitalizedNameOneLetterOff() {
        XCTAssertEqual(DictationVocabularySnapper.apply("Send it to Pria today.", terms: ["Priya"]),
                       "Send it to Priya today.")
        // Short names and lowercase words are left alone.
        XCTAssertEqual(DictationVocabularySnapper.apply("Ask Bob.", terms: ["Rob"]), "Ask Bob.")
        XCTAssertEqual(DictationVocabularySnapper.apply("send it to pria", terms: ["Priya"]), "send it to pria")
    }

    func testKeepsPunctuationAndLineBreaks() {
        XCTAssertEqual(DictationVocabularySnapper.apply("(dictator)", terms: ["Dictator"]), "(Dictator)")
        XCTAssertEqual(DictationVocabularySnapper.apply("dic\ntator", terms: ["Dictator"]), "dic\ntator")
    }

    func testNoTermsLeavesTextAlone() {
        XCTAssertEqual(DictationVocabularySnapper.apply("Hello there", terms: []), "Hello there")
        XCTAssertEqual(DictationVocabularySnapper.apply("Hello there", terms: ["ok"]), "Hello there")
    }
}

@MainActor
final class ParakeetDictationEngineTests: XCTestCase {
    func testDictatorOffersOnlyEnglishUnifiedTier() {
        XCTAssertEqual(ParakeetModel.preferred(for: "en-CA"), .englishUnified)
        XCTAssertEqual(ParakeetModel.preferred(for: "fr-CA"), .englishUnified)
        XCTAssertEqual(ParakeetModel.allCases, [.englishUnified])
        XCTAssertTrue(ParakeetModel.englishUnified.supports(localeIdentifier: "en-US"))
        XCTAssertFalse(ParakeetModel.englishUnified.supports(localeIdentifier: "fr-FR"))
        XCTAssertFalse(ParakeetModel.englishUnified.supports(localeIdentifier: "de-DE"))
        XCTAssertEqual(ParakeetModel.englishUnified.configuration.contextSuffix, "70_7_7")
    }

    func testExistingModelSelectionMigratesToUltra() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "parakeet-\(UUID().uuidString)"))
        defaults.set("parakeet-tdt-0.6b-v2", forKey: ParakeetDictationEngine.modelKey)

        let engine = ParakeetDictationEngine(modelRoot: root, defaults: defaults)
        XCTAssertEqual(engine.model, .englishUnified)
        XCTAssertEqual(defaults.string(forKey: ParakeetDictationEngine.modelKey), ParakeetModel.englishUnified.rawValue)
    }

    func testAMissingModelAsksForTheDownload() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "parakeet-\(UUID().uuidString)"))
        let engine = ParakeetDictationEngine(modelRoot: root, defaults: defaults)
        XCTAssertEqual(engine.model, .englishUnified)
        XCTAssertEqual(engine.phase, .notDownloaded)
        XCTAssertFalse(engine.isDownloaded)
        XCTAssertTrue(engine.statusDescription.contains("downloaded once"))
        XCTAssertFalse(engine.warmUp().isCancelled)
    }

    func testTranscribingWithoutAModelFailsSoAppleSpeechCanTakeOver() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let engine = ParakeetDictationEngine(modelRoot: root, model: .englishUnified)
        do {
            _ = try await engine.transcribe([])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ParakeetRecognizerError, .notLoaded)
        }
    }

    func testLegacyCacheCleanupRemovesOnlyFormerModelFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appending(path: "parakeet-tdt-0.6b-v2"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: "parakeet-tdt-0.6b-v3"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: "parakeet-ultra"), withIntermediateDirectories: true)
        let other = root.appending(path: "unrelated-cache", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: other, withIntermediateDirectories: true)
        let marker = other.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: marker)

        ParakeetDictationEngine.removeLegacyModelCaches(in: root)

        XCTAssertFalse(fileManager.fileExists(atPath: root.appending(path: "parakeet-tdt-0.6b-v2").path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appending(path: "parakeet-tdt-0.6b-v3").path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appending(path: "parakeet-ultra").path))
        XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
    }

    func testLongTermsSnapWhenHeardAFewLettersOff() {
        let terms = ["Wispr Flow"]
        XCTAssertEqual(DictationVocabularySnapper.apply("Whisperflow is the benchmark.", terms: terms),
                       "Wispr Flow is the benchmark.")
        XCTAssertEqual(DictationVocabularySnapper.apply("We are building a Whisper flow alternative", terms: terms),
                       "We are building a Wispr Flow alternative")
        XCTAssertEqual(DictationVocabularySnapper.apply("The wind will flow and whisper", terms: terms),
                       "The wind will flow and whisper")
    }

    func testDownloadIfNeededSkipsAModelTheUserRemoved() throws {
        let suite = "dictator.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defaults.set(true, forKey: "parakeetModelRemovedByUser")
        let engine = ParakeetDictationEngine(modelRoot: root, model: .englishUnified, defaults: defaults)
        XCTAssertFalse(engine.downloadIfNeeded())
        XCTAssertEqual(engine.phase, .notDownloaded)
    }

    func testBuiltInTechNamesFixCommonMisrecognitions() {
        let terms = DictationContextHints.builtInWords
        XCTAssertEqual(DictationVocabularySnapper.apply("I deploy through Vercell now", terms: terms),
                       "I deploy through Vercel now")
        XCTAssertEqual(DictationVocabularySnapper.apply("push it to github", terms: terms), "push it to GitHub")
        XCTAssertEqual(DictationVocabularySnapper.apply("write it in type script", terms: terms),
                       "write it in TypeScript")
    }

    func testModeHintsAreNotTreatedAsVocabulary() {
        XCTAssertTrue(AppModel.modeHints(for: .code).contains("camelCase"))
        XCTAssertTrue(AppModel.modeHints(for: .natural).isEmpty)
    }
}
