import SwiftUI
import XCTest
@testable import Dictator

final class PillPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 25, width: 1000, height: 700)
    private let size = CGSize(width: 120, height: 40)

    func testDefaultIsBottomCentre() {
        let origin = PillPlacement.origin(size: size, in: visible, centerFraction: 0.5)
        XCTAssertEqual(origin.x, 440)
        XCTAssertEqual(origin.y, 25 + PillPlacement.bottomInset)
    }

    func testPillNeverLeavesTheScreen() {
        XCTAssertEqual(PillPlacement.origin(size: size, in: visible, centerFraction: 0).x, PillPlacement.edgeInset)
        XCTAssertEqual(PillPlacement.origin(size: size, in: visible, centerFraction: 1).x,
                       1000 - PillPlacement.edgeInset - 120)
        XCTAssertEqual(PillPlacement.origin(size: size, in: visible, centerFraction: 7).x,
                       1000 - PillPlacement.edgeInset - 120)
    }

    func testDragFractionRoundTripsAndClamps() {
        let fraction = PillPlacement.fraction(centerX: 250, width: 120, in: visible)
        XCTAssertEqual(fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(PillPlacement.origin(size: size, in: visible, centerFraction: fraction).x, 190)
        XCTAssertEqual(PillPlacement.fraction(centerX: -500, width: 120, in: visible), 0.068, accuracy: 0.0001)
    }

    func testDropNearTheMiddleSnapsToCentre() {
        XCTAssertEqual(PillPlacement.snapped(0.46), 0.5)
        XCTAssertEqual(PillPlacement.snapped(0.55), 0.5)
        XCTAssertEqual(PillPlacement.snapped(0.35), 0.35)
    }

    func testSecondScreenUsesItsOwnFrame() {
        let right = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let origin = PillPlacement.origin(size: size, in: right, centerFraction: 0.5)
        XCTAssertEqual(origin.x, 1340)
        XCTAssertEqual(origin.y, PillPlacement.bottomInset)
    }

    func testDockOnLeftAdjustsVisibleMinX() {
        // Dock is on the left, taking 70 pt: visible.minX = 70
        let leftDockVisible = CGRect(x: 70, y: 0, width: 1370, height: 900)
        let origin = PillPlacement.origin(size: size, in: leftDockVisible, centerFraction: 0.5)
        // Center of 1370 is 70 + 685 = 755; pill origin = 755 - 60 = 695
        XCTAssertEqual(origin.x, 695)
        XCTAssertEqual(origin.y, PillPlacement.bottomInset)
    }

    func testDockOnRightAdjustsVisibleWidth() {
        // Dock is on the right, taking 70 pt: visible.width = 1370
        let rightDockVisible = CGRect(x: 0, y: 0, width: 1370, height: 900)
        let origin = PillPlacement.origin(size: size, in: rightDockVisible, centerFraction: 0.5)
        XCTAssertEqual(origin.x, 625)
        XCTAssertEqual(origin.y, PillPlacement.bottomInset)
    }
}

final class PillHitTestTests: XCTestCase {
    @MainActor
    func testClicksOutsideActiveContentRectPassThrough() {
        let hosting = FirstMouseHostingView(rootView: Text("Hello"))
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 84)
        // Set active content rect to bottom center representing idle pill (e.g. 62 x 29)
        hosting.activeContentRect = NSRect(x: 79, y: 0, width: 62, height: 29)

        // Point above the idle pill (transparent window area)
        let abovePoint = NSPoint(x: 110, y: 55)
        XCTAssertNil(hosting.hitTest(abovePoint), "Clicks above the idle pill must pass through to apps underneath")

        // Point to the left of the idle pill
        let leftPoint = NSPoint(x: 20, y: 15)
        XCTAssertNil(hosting.hitTest(leftPoint), "Clicks to the side of the idle pill must pass through")

        // Point inside the active content rect
        let insidePoint = NSPoint(x: 110, y: 15)
        XCTAssertNotNil(hosting.hitTest(insidePoint), "Clicks inside the pill must be handled")
    }
}

final class PillResizeGenerationTests: XCTestCase {
    func testNewGeometryInvalidatesOlderDelayedShrinks() {
        var generation = PillResizeGeneration()
        let firstHover = generation.next()
        let leave = generation.next()

        XCTAssertFalse(generation.matches(firstHover))
        XCTAssertTrue(generation.matches(leave))
    }

    func testHidingPillInvalidatesPendingResize() {
        var generation = PillResizeGeneration()
        let pendingShrink = generation.next()
        _ = generation.next() // hide() invalidates queued geometry callbacks

        XCTAssertFalse(generation.matches(pendingShrink))
    }
}
