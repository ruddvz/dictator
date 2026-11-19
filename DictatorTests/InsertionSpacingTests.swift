import XCTest
@testable import Dictator

final class InsertionSpacingTests: XCTestCase {
    func testAddsASpaceAfterAWordOrSentence() {
        XCTAssertEqual(TextInsertionService.spaced("I don't", after: "?"), " I don't")
        XCTAssertEqual(TextInsertionService.spaced("and more", after: "d"), " and more")
    }

    func testLeavesTextAloneWhereASpaceWouldBeWrong() {
        XCTAssertEqual(TextInsertionService.spaced("Hello", after: nil), "Hello")
        XCTAssertEqual(TextInsertionService.spaced("Hello", after: " "), "Hello")
        XCTAssertEqual(TextInsertionService.spaced("Hello", after: "\n"), "Hello")
        XCTAssertEqual(TextInsertionService.spaced("Hello", after: "("), "Hello")
        XCTAssertEqual(TextInsertionService.spaced(", then", after: "d"), ", then")
        XCTAssertEqual(TextInsertionService.spaced(" spaced", after: "d"), " spaced")
    }

    func testReadsTheCharacterBeforeTheCursor() {
        let value = "How's it going?"
        let end = CFRange(location: (value as NSString).length, length: 0)
        XCTAssertEqual(TextInsertionService.spacedInsertion("I don't", fieldValue: value, selectedRange: end), " I don't")
        XCTAssertEqual(TextInsertionService.spacedInsertion("Hi", fieldValue: value, selectedRange: CFRange(location: 0, length: 0)), "Hi")
        XCTAssertEqual(TextInsertionService.spacedInsertion("ok", fieldValue: "Done 👍", selectedRange: CFRange(location: 7, length: 0)), " ok")
    }

    func testDirectInsertionRequiresTheExactExpectedFieldValue() {
        XCTAssertEqual(
            TextInsertionService.directInsertionVerification(originalValue: "Hello", expectedValue: "Hello world", observedValue: "Hello world"),
            .verified)
        XCTAssertEqual(
            TextInsertionService.directInsertionVerification(originalValue: "Hello", expectedValue: "Hello world", observedValue: "Hello"),
            .unchanged)
        XCTAssertEqual(
            TextInsertionService.directInsertionVerification(originalValue: "Hello", expectedValue: "Hello world", observedValue: "Hello wor"),
            .changedUnexpectedly)
    }
}
