import XCTest
@testable import HushKey

final class AudioLevelMailboxTests: XCTestCase {
    func testCoalescesQueuedLevelsAndKeepsThePeak() {
        let mailbox = AudioLevelMailbox()

        XCTAssertTrue(mailbox.offer(0.2, at: 1.0))
        XCTAssertFalse(mailbox.offer(0.9, at: 1.01))

        let first = mailbox.take()
        XCTAssertEqual(first.level, 0.9, accuracy: 0.0001)
        XCTAssertEqual(first.peak, 0.9, accuracy: 0.0001)
    }

    func testMeterDeliveryIsLimitedToSixtyPerSecond() {
        let mailbox = AudioLevelMailbox()

        XCTAssertTrue(mailbox.offer(0.3, at: 2.0))
        _ = mailbox.take()
        XCTAssertFalse(mailbox.offer(0.4, at: 2.01))
        XCTAssertTrue(mailbox.offer(0.5, at: 2.02))

        let update = mailbox.take()
        XCTAssertEqual(update.level, 0.5, accuracy: 0.0001)
        XCTAssertEqual(update.peak, 0.5, accuracy: 0.0001)
    }

    func testResetClearsPendingLevelsAndRestartsTheThrottle() {
        let mailbox = AudioLevelMailbox()
        XCTAssertTrue(mailbox.offer(0.8, at: 3.0))

        mailbox.reset()

        let update = mailbox.take()
        XCTAssertEqual(update.level, 0, accuracy: 0.0001)
        XCTAssertEqual(update.peak, 0, accuracy: 0.0001)
        XCTAssertTrue(mailbox.offer(0.2, at: 3.01))
    }
}
