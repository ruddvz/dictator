import XCTest
@testable import HushKey

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

    func testSecondScreenUsesItsOwnFrame() {
        let right = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let origin = PillPlacement.origin(size: size, in: right, centerFraction: 0.5)
        XCTAssertEqual(origin.x, 1340)
        XCTAssertEqual(origin.y, PillPlacement.bottomInset)
    }
}

final class AudioDeviceFilterTests: XCTestCase {
    func testPrivateAggregatesAreHidden() {
        XCTAssertFalse(AudioDevices.isUserFacing("CADefaultDeviceAggregate-22075-0"))
        XCTAssertTrue(AudioDevices.isUserFacing("MacBook Pro Microphone"))
    }
}
