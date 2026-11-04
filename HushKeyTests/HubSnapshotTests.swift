import SwiftUI
import XCTest
@testable import HushKey

/// Writes each hub screen to PNG (light and dark) when HUSHKEY_SNAPSHOT_DIR is set, for design
/// reviews. Skipped otherwise. AppKit-backed controls may render as placeholders.
@MainActor
final class HubSnapshotTests: XCTestCase {
    func testRenderHubScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["HUSHKEY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set HUSHKEY_SNAPSHOT_DIR to render hub snapshots")
        }
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let model = AppModel(dictationHistoryURL: temp.appending(path: "h.json"),
                             fileTranscriptionHistoryURL: temp.appending(path: "f.json"))
        let screens: [(String, AnyView)] = [
            ("dictation", AnyView(DictationView())), ("transforms", AnyView(TransformView())),
            ("files", AnyView(FileTranscriptionView())), ("meetings", AnyView(MeetingNotesView())),
            ("personalization", AnyView(PersonalizationView())), ("style", AnyView(StyleView())),
            ("insights", AnyView(InsightsView())), ("settings", AnyView(SettingsView())),
        ]
        for (name, screen) in screens {
            for scheme in [ColorScheme.light, .dark] {
                let view = screen
                    .environment(model)
                    .frame(width: 900, height: 1400, alignment: .top)
                    .background(Theme.paper)
                    .environment(\.colorScheme, scheme)
                // A real (off-screen) window, so scroll views and AppKit controls draw.
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 1400)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = hosting
                window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                window.orderFrontRegardless()
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                    XCTFail("render \(name)"); continue
                }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                window.orderOut(nil)
                guard let png = rep.representation(using: .png, properties: [:]) else { XCTFail("png \(name)"); continue }
                try png.write(to: URL(fileURLWithPath: dir).appending(path: "hub-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
