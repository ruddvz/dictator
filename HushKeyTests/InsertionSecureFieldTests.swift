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

/// The unverified ⌘V fallback must only fire where there is somewhere to type.
final class UnverifiedPasteGateTests: XCTestCase {
    private func allows(_ role: String, _ subrole: String = "", settable: Bool = false, editable: Bool = false) -> Bool {
        TextInsertionService.allowsUnverifiedPaste(role: role, subrole: subrole,
                                                   selectedTextSettable: settable, hasEditableAncestor: editable)
    }

    func testAllowsTextRoles() {
        XCTAssertTrue(allows("AXTextArea"))
        XCTAssertTrue(allows("AXTextField"))
    }

    func testAllowsContentEditableSignals() {
        XCTAssertTrue(allows("AXGroup", editable: true))
        XCTAssertTrue(allows("AXWebArea", settable: true))
    }

    func testRejectsNonTextFocus() {
        XCTAssertFalse(allows("AXList"))       // Finder icons
        XCTAssertFalse(allows("AXWebArea"))    // a page with no field focused
        XCTAssertFalse(allows("AXButton"))
        XCTAssertFalse(allows(""))
    }

    func testRejectsPasswordFieldsEvenWhenEditable() {
        XCTAssertFalse(allows("AXTextField", "AXSecureTextField", settable: true, editable: true))
        XCTAssertFalse(allows("AXGroup", "AXPasswordField", editable: true))
    }

    func testClipboardRestoreWaitsForSlowApps() {
        XCTAssertGreaterThanOrEqual(TextInsertionService.unverifiedPasteRestoreDelay, .milliseconds(400))
    }
}
