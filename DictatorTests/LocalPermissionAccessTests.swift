import XCTest
@testable import Dictator

final class LocalPermissionAccessTests: XCTestCase {
    func testPermissionCallbackWinsOverTimeout() async {
        let outcome = await LocalPermissionAccess.waitForOutcome(timeout: 1) { complete in
            complete(.authorized)
        }

        XCTAssertEqual(outcome, .authorized)
    }

    func testUnansweredPermissionRequestTimesOut() async {
        let outcome = await LocalPermissionAccess.waitForOutcome(timeout: 0.02) { _ in }

        XCTAssertEqual(outcome, .timedOut)
    }

    func testCancellingPermissionRequestResolvesImmediately() async {
        let request = Task {
            await LocalPermissionAccess.waitForOutcome(timeout: 5) { _ in }
        }
        request.cancel()

        let outcome = await request.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testOnlyTheFirstPermissionResultIsUsed() async {
        let outcome = await LocalPermissionAccess.waitForOutcome(timeout: 1) { complete in
            complete(.denied)
            complete(.authorized)
        }

        XCTAssertEqual(outcome, .denied)
    }
}
