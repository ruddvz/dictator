import XCTest
@testable import HushKey

final class LivePhraseFinalizerTests: XCTestCase {
    private func typed(_ phrases: [LivePhraseFinalizer.Phrase?]) -> String {
        phrases.compactMap { $0 }.reduce("") { result, phrase in
            var piece = phrase.leadingPunctuation
            if !phrase.words.isEmpty { piece += (piece.isEmpty ? "" : " ") + phrase.words }
            return LiveTypingSession.joined(result, piece)
        }
    }

    func testNothingIsFinalWhileWordsKeepChanging() {
        var finalizer = LivePhraseFinalizer()
        XCTAssertNil(finalizer.update(transcript: "I", at: 0))
        XCTAssertNil(finalizer.update(transcript: "I think", at: 0.3))
        XCTAssertNil(finalizer.update(transcript: "I think we", at: 0.6))
        XCTAssertNil(finalizer.advance(to: 0.7))
        XCTAssertEqual(finalizer.pendingWords, ["I", "think", "we"])
    }

    func testStableWordsFinalizeButTheNewestWaitForMore() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "I think we should", at: 0)
        _ = finalizer.update(transcript: "I think we should meet", at: 0.5)
        // "I think we should" has been unchanged for 0.8 s; "meet on" are the two held back.
        let phrase = finalizer.update(transcript: "I think we should meet on", at: 0.9)
        XCTAssertEqual(phrase?.words, "I think we should")
        XCTAssertEqual(finalizer.pendingWords, ["meet", "on"])
    }

    func testFewerThanAPhraseWaitsUnlessAClauseEnds() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "Hello there friend", at: 0)
        XCTAssertNil(finalizer.update(transcript: "Hello there friend of", at: 0.9), "two settled words are not yet a phrase")

        var clause = LivePhraseFinalizer()
        _ = clause.update(transcript: "Yes, I think so", at: 0)
        XCTAssertEqual(clause.advance(to: 0.9)?.words, "Yes,", "a comma ends a phrase early")
    }

    func testPauseFinalizesEverything() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "see you", at: 0)
        _ = finalizer.update(transcript: "see you soon", at: 0.2)
        XCTAssertNil(finalizer.advance(to: 1.1))
        XCTAssertEqual(finalizer.advance(to: 1.2)?.words, "see you soon")
        XCTAssertTrue(finalizer.pendingWords.isEmpty)
        XCTAssertNil(finalizer.advance(to: 3), "nothing is handed out twice")
    }

    func testRevisedTailResetsItsClock() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "I scream for you now", at: 0)
        // Speech rewrites the start; those words are new again.
        XCTAssertNil(finalizer.update(transcript: "Ice cream for you now", at: 0.7))
        XCTAssertNil(finalizer.advance(to: 1.0))
        XCTAssertEqual(finalizer.advance(to: 1.5)?.words, "Ice cream for")
    }

    func testLongRunsAreCappedEvenWhileChanging() {
        var finalizer = LivePhraseFinalizer(rules: .init(maximumPendingWords: 5))
        let phrase = finalizer.update(transcript: "one two three four five six", at: 0)
        XCTAssertEqual(phrase?.words, "one two three four")
    }

    func testFinalizedWordsAreNeverRepeatedAsTheTranscriptGrows() {
        var finalizer = LivePhraseFinalizer()
        var out: [LivePhraseFinalizer.Phrase?] = []
        out.append(finalizer.update(transcript: "we can meet", at: 0))
        out.append(finalizer.advance(to: 1.2))
        out.append(finalizer.update(transcript: "we can meet at four", at: 1.5))
        out.append(finalizer.advance(to: 2.6))
        out.append(finalizer.finish(transcript: "we can meet at four"))
        XCTAssertEqual(typed(out), "we can meet at four")
    }

    func testFullStopAddedToATypedWordIsAppendedNotRetyped() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "hello world", at: 0)
        XCTAssertEqual(finalizer.advance(to: 1.1)?.words, "hello world")
        // The stitcher ends the earlier phrase once a new sentence starts.
        _ = finalizer.update(transcript: "hello world. How are you today", at: 1.5)
        _ = finalizer.update(transcript: "hello world. How are you today so", at: 1.6)
        let next = finalizer.advance(to: 2.4)
        XCTAssertEqual(next?.leadingPunctuation, ".")
        XCTAssertEqual(next?.words, "How are you")
        XCTAssertEqual(typed([.init(words: "hello world"), next, finalizer.finish(transcript: "hello world. How are you today so?")]),
                       "hello world. How are you today so?")
    }

    func testPunctuationOnlyAfterAPause() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "thanks", at: 0)
        XCTAssertEqual(finalizer.advance(to: 1.0)?.words, "thanks")
        // Already paused, so the full stop Speech adds goes in straight away, on its own.
        XCTAssertEqual(finalizer.update(transcript: "Thanks.", at: 1.2), .init(leadingPunctuation: ".", words: ""))
        XCTAssertTrue(finalizer.finish(transcript: "Thanks.").isEmpty)
    }

    func testAlignsWhenSpeechMergesEarlierWords() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "I can not come today", at: 0)
        XCTAssertEqual(finalizer.advance(to: 1.0)?.words, "I can not come today")
        // "can not" became "cannot": one fewer word before the new ones.
        let rest = finalizer.finish(transcript: "I cannot come today but tomorrow works")
        XCTAssertEqual(rest.words, "but tomorrow works")
    }

    func testFinishAfterTheTranscriptShrinksTypesNothingMore() {
        var finalizer = LivePhraseFinalizer()
        _ = finalizer.update(transcript: "one two three", at: 0)
        _ = finalizer.advance(to: 1.0)
        XCTAssertTrue(finalizer.finish(transcript: "one").isEmpty)
    }

    func testEligibility() {
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: false, hasReadableField: true, isElectron: false,
                                                    usesParakeet: false, mode: .natural), .settingOff)
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: true, hasReadableField: false, isElectron: false,
                                                    usesParakeet: false, mode: .natural), .noReadableField)
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: true, hasReadableField: true, isElectron: true,
                                                    usesParakeet: false, mode: .natural), .electron)
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: true, hasReadableField: true, isElectron: false,
                                                    usesParakeet: true, mode: .natural), .parakeet)
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: true, hasReadableField: true, isElectron: false,
                                                    usesParakeet: false, mode: .code), .codeMode)
        XCTAssertEqual(LiveTypingEligibility.decide(enabled: true, hasReadableField: true, isElectron: false,
                                                    usesParakeet: false, mode: .message), .eligible)
    }

    func testSessionKeepsTypedAndUntypedApartAndDeliveryKnown() {
        var session = LiveTypingSession(startedAt: 0)
        XCTAssertFalse(session.hasDelivered)
        session.recordTyped("We can meet")
        session.recordTyped(", at four")
        session.state = .stopped
        session.recordUntyped("if that works.")
        XCTAssertTrue(session.hasDelivered)
        XCTAssertEqual(session.text, "We can meet, at four if that works.")

        var unsure = LiveTypingSession(startedAt: 0)
        unsure.state = .uncertain
        XCTAssertTrue(unsure.hasDelivered, "a maybe-typed phrase must not be typed again at the end")
    }

    func testSpokenLineBreaksSurviveAtPhraseEdges() {
        XCTAssertEqual(LiveTypingSession.keepingLineBreaks(of: "thanks new line", mode: .message, in: "thanks"),
                       "thanks\n")
        XCTAssertEqual(LiveTypingSession.keepingLineBreaks(of: "new paragraph best", mode: .email, in: "best"),
                       "\n\nbest")
        XCTAssertEqual(LiveTypingSession.keepingLineBreaks(of: "new line", mode: .natural, in: "new line"),
                       "new line")
    }
}
