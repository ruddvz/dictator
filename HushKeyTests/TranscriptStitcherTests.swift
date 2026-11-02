import XCTest
@testable import HushKey

final class TranscriptStitcherTests: XCTestCase {
    func testKeepsFirstPhraseWhenSpeechRestartsAfterAPause() {
        var stitcher = TranscriptStitcher()
        stitcher.update(partial: "Let's meet", start: 0.4, end: 1.0)
        stitcher.update(partial: "Let's meet at three thirty", start: 0.4, end: 2.1)
        // Two seconds of silence, then Speech reports only the new phrase.
        stitcher.update(partial: "Bring the roadmap", start: 4.3, end: 5.2)
        stitcher.update(partial: "Bring the roadmap please.", start: 4.3, end: 5.9)
        XCTAssertEqual(stitcher.text, "Let's meet at three thirty. Bring the roadmap please.")
    }

    func testRevisionsOfTheSamePhraseReplaceInsteadOfRepeating() {
        var stitcher = TranscriptStitcher()
        stitcher.update(partial: "Hay how", start: 0.3, end: 0.9)
        stitcher.update(partial: "Hey, how's it going?", start: 0.3, end: 1.8)
        XCTAssertEqual(stitcher.text, "Hey, how's it going?")
    }

    func testTaskEndingOnSilenceKeepsTheLastPartial() {
        var stitcher = TranscriptStitcher()
        stitcher.update(partial: "First thought", start: 0.2, end: 1.0)
        stitcher.commit() // "No speech detected" ended the task with no final text
        stitcher.update(partial: "second thought", start: 0.1, end: 0.8) // new task, timings restart
        XCTAssertEqual(stitcher.text, "First thought second thought")
    }

    func testWithoutTimingsAShorterUnrelatedPartialIsANewPhrase() {
        var stitcher = TranscriptStitcher()
        stitcher.update(partial: "Send the invoice to Priya today")
        stitcher.update(partial: "Thanks")
        XCTAssertEqual(stitcher.text, "Send the invoice to Priya today. Thanks")

        var revising = TranscriptStitcher()
        revising.update(partial: "Send the invoice")
        revising.update(partial: "Send the invoices to Priya")
        XCTAssertEqual(revising.text, "Send the invoices to Priya")
    }

    func testLowercaseContinuationAndIDoNotGetAPeriod() {
        XCTAssertEqual(TranscriptStitcher.join("I was thinking", "maybe tomorrow"), "I was thinking maybe tomorrow")
        XCTAssertEqual(TranscriptStitcher.join("So yesterday", "I went home"), "So yesterday I went home")
        XCTAssertEqual(TranscriptStitcher.join("Done.", "Next"), "Done. Next")
    }

    func testReplacedTextIsKeptAsCommitted() {
        var stitcher = TranscriptStitcher(text: "Earlier text")
        stitcher.update(partial: "more", start: 0.1, end: 0.4)
        XCTAssertEqual(stitcher.text, "Earlier text more")
    }

    func testSilenceErrorsAreNotShownAsProblems() {
        XCTAssertTrue(MicTranscriber.SpeechResult.isBenign(domain: "kAFAssistantErrorDomain", code: 1110))
        XCTAssertFalse(MicTranscriber.SpeechResult.isBenign(domain: "kAFAssistantErrorDomain", code: 1700))
    }
}
