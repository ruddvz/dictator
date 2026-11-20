import XCTest
@testable import Dictator

final class DictationCleanupTests: XCTestCase {
    private func clean(_ text: String) -> String {
        DictationLocalCleanup.removeFillers(from: DictationBacktrack.apply(to: text))
    }

    func testSelfCorrectionsKeepOnlyWhatWasMeant() {
        XCTAssertEqual(clean("I need to leave at four PM no actually 5 PM"), "I need to leave at 5 PM")
        XCTAssertEqual(clean("I need to leave at four PM, no, actually 5 PM."), "I need to leave at 5 PM.")
        XCTAssertEqual(clean("I need to leave at four PM. No, actually 5 PM."), "I need to leave at 5 PM.")
        XCTAssertEqual(clean("Call me at five, no six."), "Call me at six.")
        XCTAssertEqual(clean("Book a table for four, actually five."), "Book a table for five.")
        XCTAssertEqual(clean("Let's meet on Tuesday, no wait, on Wednesday."), "Let's meet on Wednesday.")
        XCTAssertEqual(clean("Let's meet Friday afternoon, actually Thursday."), "Let's meet Thursday afternoon.")
        XCTAssertEqual(clean("She has two kids no three"), "She has three kids")
        XCTAssertEqual(clean("I want the red one no the blue one"), "I want the blue one")
        XCTAssertEqual(clean("Send it to Alice, actually Bob."), "Send it to Bob.")
        XCTAssertEqual(clean("Create a file called notes, actually todo."), "Create a file called todo.")
        XCTAssertEqual(clean("I want to go to the park, actually I want to go to the beach."),
                       "I want to go to the beach.")
        XCTAssertEqual(clean("Send the report to the team, sorry, I mean the managers."),
                       "Send the report to the managers.")
        XCTAssertEqual(clean("Order two coffees, make that three coffees."), "Order three coffees.")
    }

    func testScratchThatDropsWhatCameBefore() {
        XCTAssertEqual(clean("Use the old route, scratch that, new route."), "Use the new route.")
        XCTAssertEqual(clean("Hi Sam. Send it Monday. Scratch that. Send it Tuesday."), "Hi Sam. Send it Tuesday.")
        XCTAssertEqual(clean("Thanks for the update. This is wrong. Never mind."), "Thanks for the update.")
    }

    func testOrdinarySentencesAreLeftAlone() {
        for sentence in [
            "Yes, actually it works.",
            "I actually like it.",
            "We could actually use the new one.",
            "There is no way we finish today.",
            "I have no idea where it is.",
            "Sorry I'm late, the train was slow.",
            "I can't wait to see you on Friday.",
            "Give me no more than 5 minutes.",
            "Let me know by Friday, no rush.",
            "I mean it.",
            "It was good, actually great.",
            "I like the first option.",
            "The U.S. office opens at nine.",
            "Uh-oh, that was close. Mm-hmm, sure.",
            "The umbrella is here.",
            "ER is the emergency room.",
            "Bye bye, see you soon.",
            "It's very very important.",
            "I know that that is true.",
            "You know the answer.",
        ] {
            XCTAssertEqual(clean(sentence), sentence)
        }
    }

    func testFillersStuttersAndTicsAreRemoved() {
        XCTAssertEqual(clean("Um, could you, uh, send it?"), "Could you send it?")
        XCTAssertEqual(clean("But um ah u h u um um and those kind of words"), "But and those kind of words")
        XCTAssertEqual(clean("Umm I'll be there, erm, soon."), "I'll be there soon.")
        XCTAssertEqual(clean("I I need the the report."), "I need the report.")
        XCTAssertEqual(clean("I need I need to go."), "I need to go.")
        XCTAssertEqual(clean("So, like, I was, like, thinking we should go."), "So I was thinking we should go.")
        XCTAssertEqual(clean("You know, it's fine. Basically, it works."), "It's fine. It works.")
        XCTAssertEqual(clean("Hmm, let me think. Ah, right."), "Let me think. Right.")
        XCTAssertEqual(clean("We should uh ship it today."), "We should ship it today.")
        XCTAssertEqual(clean("Basically we should launch this today."), "We should launch this today.")
        XCTAssertEqual(clean("We can meet at like 5 PM."), "We can meet at 5 PM.")
        XCTAssertEqual(clean("I was like thinking about that."), "I was thinking about that.")
        XCTAssertEqual(clean("Um like we should go."), "We should go.")
    }

    func testSmartCleanupMayOnlyDropFillersAndStutters() {
        XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(
            from: "So yeah I was thinking like we could uh ship it Friday.", to: "I was thinking we could ship it Friday."))
        XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(from: "um it's like really good, you know.",
                                                          to: "It's really good."))
        XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(from: "check in about the the launch",
                                                          to: "Check in about the launch."))
        XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(from: "I need four tickets", to: "I need 4 tickets."))
        // Dropping real words, rewording, reordering, additions, answers and lost punctuation are refused.
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "push it to Tuesday no wait Wednesday",
                                                           to: "push it to Tuesday Wednesday"))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "can you send it", to: "can send it"))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "I need to leave at five", to: "I must leave at five."))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "I'm gonna go", to: "I'm going to go."))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "send it today", to: "today send it"))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "what is the capital of France",
                                                           to: "The capital of France is Paris."))
        XCTAssertFalse(DictationSmartCleanup.isSafeCleanup(from: "Hi Sam. Thanks, see you. Bye.",
                                                           to: "Hi Sam thanks see you bye"))
    }
}
