import XCTest
@testable import HushKey

final class FunctionKeyGestureTests: XCTestCase {
    func testHoldStartsAfterDelayAndEndsOnRelease() {
        var gesture = FunctionKeyGesture()
        XCTAssertEqual(gesture.fnDown(at: 0), .scheduleHoldStart)
        XCTAssertEqual(gesture.holdDelayElapsed(), .startHold)
        XCTAssertEqual(gesture.fnUp(at: 1.5), .endHold)
    }

    func testFnWithAnotherKeyIsAShortcutNotDictation() {
        var gesture = FunctionKeyGesture()
        _ = gesture.fnDown(at: 0)
        XCTAssertEqual(gesture.otherKeyDown(), .cancelHoldStart)
        XCTAssertEqual(gesture.holdDelayElapsed(), .none)
        XCTAssertEqual(gesture.fnUp(at: 0.5), .none)

        _ = gesture.fnDown(at: 2)
        _ = gesture.holdDelayElapsed()
        XCTAssertEqual(gesture.otherKeyDown(), .abortHold)
    }

    func testDoubleTapStartsHandsFreeAndNextPressStops() {
        var gesture = FunctionKeyGesture()
        _ = gesture.fnDown(at: 0)
        XCTAssertEqual(gesture.fnUp(at: 0.08), .cancelHoldStart)
        _ = gesture.fnDown(at: 0.25)
        XCTAssertEqual(gesture.fnUp(at: 0.33), .startHandsFree)
        XCTAssertTrue(gesture.isHandsFree)
        XCTAssertEqual(gesture.fnDown(at: 5), .stopHandsFree)
        XCTAssertEqual(gesture.fnUp(at: 5.1), .none)
        XCTAssertFalse(gesture.isHandsFree)
    }

    func testSlowTapsDoNotStartHandsFree() {
        var gesture = FunctionKeyGesture()
        _ = gesture.fnDown(at: 0)
        _ = gesture.fnUp(at: 0.08)
        _ = gesture.fnDown(at: 1)
        XCTAssertEqual(gesture.fnUp(at: 1.08), .cancelHoldStart)
        XCTAssertFalse(gesture.isHandsFree)
    }

    func testOpeningModalPanelEndsHeldDictationAndIgnoresTheLaterRelease() {
        var gesture = FunctionKeyGesture()
        _ = gesture.fnDown(at: 0)
        XCTAssertEqual(gesture.holdDelayElapsed(), .startHold)

        XCTAssertEqual(gesture.modalPanelDidOpen(), .endHold)
        XCTAssertEqual(gesture.fnUp(at: 1), .none)
    }

    func testOpeningModalPanelStopsHandsFreeDictation() {
        var gesture = FunctionKeyGesture()
        _ = gesture.fnDown(at: 0)
        _ = gesture.fnUp(at: 0.08)
        _ = gesture.fnDown(at: 0.25)
        XCTAssertEqual(gesture.fnUp(at: 0.33), .startHandsFree)

        XCTAssertEqual(gesture.modalPanelDidOpen(), .stopHandsFree)
        XCTAssertFalse(gesture.isHandsFree)
    }

    func testFnKeycapStaysOneKey() {
        XCTAssertEqual(KeycapShortcut.keys(in: "fn"), ["fn"])
        XCTAssertEqual(KeycapShortcut.keys(in: "⌥⇧D"), ["⌥", "⇧", "D"])
    }
}
