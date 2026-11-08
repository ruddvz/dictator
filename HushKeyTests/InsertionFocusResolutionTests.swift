import XCTest
@testable import HushKey

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
}
