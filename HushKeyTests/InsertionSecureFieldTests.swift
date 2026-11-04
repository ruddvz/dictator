import XCTest
@testable import HushKey

final class InsertionSecureFieldTests: XCTestCase {
    func testRejectsSecureSubrole() {
        XCTAssertFalse(TextInsertionService.isSupportedTextTarget(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    func testRejectsPasswordSubrole() {
        XCTAssertFalse(TextInsertionService.isSupportedTextTarget(role: "AXTextField", subrole: "AXPasswordField"))
    }

    func testRejectsSecureRole() {
        XCTAssertFalse(TextInsertionService.isSupportedTextTarget(role: "AXSecureTextField", subrole: ""))
    }

    func testAcceptsNormalTextField() {
        XCTAssertTrue(TextInsertionService.isSupportedTextTarget(role: "AXTextField", subrole: ""))
        XCTAssertTrue(TextInsertionService.isSupportedTextTarget(role: "AXTextArea", subrole: ""))
        XCTAssertTrue(TextInsertionService.isSupportedTextTarget(role: "AXComboBox", subrole: ""))
    }
}
