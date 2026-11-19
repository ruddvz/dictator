import AppKit
import XCTest
@testable import Dictator

final class HushIconsTests: XCTestCase {
    func testEveryNavigationAndActionIconHasAnAvailableNativeSymbol() {
        for icon in HushIcon.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil),
                            "Missing SF Symbol for \(icon.rawValue): \(icon.symbolName)")
            XCTAssertNotNil(NSImage(systemSymbolName: icon.selectedSymbolName, accessibilityDescription: nil),
                            "Missing selected SF Symbol for \(icon.rawValue): \(icon.selectedSymbolName)")
        }
    }

    func testStateIconsUseAvailableNativeSymbols() {
        for name in ["waveform", "hourglass", "checkmark.circle.fill"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "Missing state SF Symbol: \(name)")
        }
    }
}
