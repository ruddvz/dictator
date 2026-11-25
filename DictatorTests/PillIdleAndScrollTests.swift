import XCTest
import SwiftUI
@testable import Dictator

@MainActor
final class PillIdleAndScrollTests: XCTestCase {
    func testPassThroughPillIgnoresEveryClick() {
        let hosting = FirstMouseHostingView(rootView: Color.red.frame(width: 100, height: 40))
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        hosting.activeContentRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        XCTAssertNotNil(hosting.hitTest(CGPoint(x: 50, y: 20)))
        hosting.isPassThrough = true
        XCTAssertNil(hosting.hitTest(CGPoint(x: 50, y: 20)))
        XCTAssertNil(hosting.hitTest(CGPoint(x: 5, y: 5)))
    }

    func testIdleBarIsOffByDefault() {
        UserDefaults.standard.removeObject(forKey: "showIdleBar")
        XCTAssertNil(UserDefaults.standard.object(forKey: "showIdleBar"))
        XCTAssertEqual(UserDefaults.standard.object(forKey: "showIdleBar") as? Bool ?? false, false)
    }
}
