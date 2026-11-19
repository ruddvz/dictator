import XCTest
@testable import Dictator

final class InsertionFocusResolutionTests: XCTestCase {
    private struct Candidate: Equatable {
        let processIdentifier: pid_t
        let label: String
    }

    private let expectedProcessIdentifier: pid_t = 42

    private func candidate(_ label: String, pid: pid_t) -> Candidate {
        Candidate(processIdentifier: pid, label: label)
    }

    func testPrefersFocusedApplicationElementWhenItMatchesTargetProcess() {
        let application = candidate("composer", pid: expectedProcessIdentifier)
        let result = TextInsertionService.preferredFocusedElement(
            applicationFocusedElement: application,
            systemWideFocusedElement: candidate("system-wide", pid: expectedProcessIdentifier),
            frontmostApplicationFocusedElement: candidate("frontmost", pid: expectedProcessIdentifier),
            expectedProcessIdentifier: expectedProcessIdentifier,
            processIdentifier: { $0.processIdentifier })

        XCTAssertEqual(result, application)
    }

    func testSkipsFocusedApplicationElementFromAnotherProcess() {
        let systemWide = candidate("system-wide", pid: expectedProcessIdentifier)
        let result = TextInsertionService.preferredFocusedElement(
            applicationFocusedElement: candidate("stale", pid: 7),
            systemWideFocusedElement: systemWide,
            frontmostApplicationFocusedElement: candidate("frontmost", pid: expectedProcessIdentifier),
            expectedProcessIdentifier: expectedProcessIdentifier,
            processIdentifier: { $0.processIdentifier })

        XCTAssertEqual(result, systemWide)
    }

    func testFallsBackToFrontmostApplicationWhenEarlierCandidatesDoNotMatch() {
        let frontmost = candidate("frontmost", pid: expectedProcessIdentifier)
        let result = TextInsertionService.preferredFocusedElement(
            applicationFocusedElement: candidate("stale app", pid: 7),
            systemWideFocusedElement: candidate("stale system-wide", pid: 9),
            frontmostApplicationFocusedElement: frontmost,
            expectedProcessIdentifier: expectedProcessIdentifier,
            processIdentifier: { $0.processIdentifier })

        XCTAssertEqual(result, frontmost)
    }

    func testRejectsCandidatesFromOtherProcesses() {
        let result = TextInsertionService.preferredFocusedElement(
            applicationFocusedElement: candidate("stale app", pid: 7),
            systemWideFocusedElement: candidate("stale system-wide", pid: 9),
            frontmostApplicationFocusedElement: candidate("stale frontmost", pid: 11),
            expectedProcessIdentifier: expectedProcessIdentifier,
            processIdentifier: { $0.processIdentifier })

        XCTAssertNil(result)
    }

    func testFindsUniqueFocusedTextDescendantWhenFocusedElementAttributeIsMissing() {
        let composer = candidate("composer", pid: expectedProcessIdentifier)
        let result = TextInsertionService.preferredFocusedDescendant(
            candidates: [
                focusCandidate("sidebar", role: "AXTextField", focused: false, depth: 4),
                focusCandidate("composer", role: "AXTextArea", focused: true, depth: 5, element: composer),
                focusCandidate("button", role: "AXButton", focused: true, depth: 6)
            ],
            expectedProcessIdentifier: expectedProcessIdentifier,
            elementsEqual: ==)

        XCTAssertEqual(result, composer)
    }

    func testPrefersDeepestFocusedTextDescendant() {
        let leaf = candidate("editor leaf", pid: expectedProcessIdentifier)
        let result = TextInsertionService.preferredFocusedDescendant(
            candidates: [
                focusCandidate("editor container", role: "AXTextArea", focused: true, depth: 4),
                focusCandidate("editor leaf", role: "AXTextField", focused: true, depth: 6, element: leaf)
            ],
            expectedProcessIdentifier: expectedProcessIdentifier,
            elementsEqual: ==)

        XCTAssertEqual(result, leaf)
    }

    func testRejectsSecureAndWrongProcessDescendants() {
        let result = TextInsertionService.preferredFocusedDescendant(
            candidates: [
                focusCandidate("password", role: "AXTextField", subrole: "AXSecureTextField", focused: true, depth: 5),
                focusCandidate("other app", role: "AXTextArea", focused: true, depth: 6, pid: 7)
            ],
            expectedProcessIdentifier: expectedProcessIdentifier,
            elementsEqual: ==)

        XCTAssertNil(result)
    }

    func testAmbiguousFocusedTextDescendantsFailClosed() {
        let result = TextInsertionService.preferredFocusedDescendant(
            candidates: [
                focusCandidate("composer one", role: "AXTextArea", focused: true, depth: 5),
                focusCandidate("composer two", role: "AXTextArea", focused: true, depth: 5)
            ],
            expectedProcessIdentifier: expectedProcessIdentifier,
            elementsEqual: ==)

        XCTAssertNil(result)
    }

    private func focusCandidate(_ label: String, role: String, subrole: String = "",
                                focused: Bool, depth: Int, pid: pid_t? = nil,
                                element: Candidate? = nil) -> TextInsertionService.FocusCandidate<Candidate> {
        let target = element ?? candidate(label, pid: pid ?? expectedProcessIdentifier)
        return .init(element: target,
                     processIdentifier: pid ?? target.processIdentifier,
                     role: role, subrole: subrole, depth: depth,
                     isFocused: focused,
                     isPassword: subrole.localizedCaseInsensitiveContains("secure")
                        || subrole.localizedCaseInsensitiveContains("password"),
                     selectedTextSettable: false, hasEditableAncestor: false)
    }
}
