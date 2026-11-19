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
    func testEnglishDictationPrefersTheEnglishModel() {
        XCTAssertEqual(ParakeetModel.preferred(for: "en-CA"), .englishV2)
        XCTAssertEqual(ParakeetModel.preferred(for: "fr-CA"), .multilingualV3)
        XCTAssertTrue(ParakeetModel.multilingualV3.supports(localeIdentifier: "de-DE"))
        XCTAssertFalse(ParakeetModel.englishV2.supports(localeIdentifier: "de-DE"))
        XCTAssertFalse(ParakeetModel.multilingualV3.supports(localeIdentifier: "ja-JP"))
    }

    func testAMissingModelAsksForTheDownload() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "parakeet-\(UUID().uuidString)"))
        let engine = ParakeetDictationEngine(modelRoot: root, defaults: defaults)
        XCTAssertEqual(engine.model, .englishV2)
        XCTAssertEqual(engine.phase, .notDownloaded)
        XCTAssertFalse(engine.isDownloaded)
        XCTAssertTrue(engine.statusDescription.contains("downloaded once"))
        XCTAssertFalse(engine.warmUp().isCancelled)
    }

    func testTranscribingWithoutAModelFailsSoAppleSpeechCanTakeOver() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let engine = ParakeetDictationEngine(modelRoot: root, model: .englishV2)
        do {
            _ = try await engine.transcribe([])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ParakeetRecognizerError, .notLoaded)
        }
    }

    func testModeHintsAreNotTreatedAsVocabulary() {
        XCTAssertTrue(AppModel.modeHints(for: .code).contains("camelCase"))
        XCTAssertTrue(AppModel.modeHints(for: .natural).isEmpty)
    }
}
