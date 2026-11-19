import XCTest
@testable import Dictator

final class AudioDeviceFilterTests: XCTestCase {
    func testPrivateAggregatesAreHidden() {
        XCTAssertFalse(AudioDevices.isUserFacing("CADefaultDeviceAggregate-22075-0"))
        XCTAssertTrue(AudioDevices.isUserFacing("MacBook Pro Microphone"))
    }
}
