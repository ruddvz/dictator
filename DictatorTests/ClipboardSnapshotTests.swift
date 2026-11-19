import AppKit
import XCTest
@testable import Dictator

final class ClipboardSnapshotTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("dictator.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    func testPasteRestoresEveryTypeTheUserHad() {
        let item = NSPasteboardItem()
        item.setString("user copy", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let saved = ClipboardSnapshot(pasteboard)
        let ours = ClipboardSnapshot.placeTransient("dictated text", on: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
        XCTAssertTrue(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[0]) == true)

        XCTAssertTrue(saved.restore(to: pasteboard, ifChangeCountIs: ours))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copy")
        XCTAssertEqual(pasteboard.data(forType: .png), Data([1, 2, 3]))
    }

    func testRestoreNeverOverwritesANewerCopy() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let saved = ClipboardSnapshot(pasteboard)
        let ours = ClipboardSnapshot.placeTransient("dictated", on: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied meanwhile", forType: .string)

        XCTAssertFalse(saved.restore(to: pasteboard, ifChangeCountIs: ours))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
    }

    func testEmptyClipboardStaysEmptyAfterRestore() {
        pasteboard.clearContents()
        let saved = ClipboardSnapshot(pasteboard)
        let ours = ClipboardSnapshot.placeTransient("dictated", on: pasteboard)
        XCTAssertTrue(saved.restore(to: pasteboard, ifChangeCountIs: ours))
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
