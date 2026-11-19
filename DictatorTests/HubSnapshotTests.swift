import SwiftUI
import XCTest
@testable import Dictator

/// Writes each hub screen to PNG (light and dark) when TEST_RUNNER_DICTATOR_SNAPSHOT_DIR is set, for design
/// reviews. Skipped otherwise. AppKit-backed controls may render as placeholders.
@MainActor
final class HubSnapshotTests: XCTestCase {
    func testRenderHubScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["TEST_RUNNER_DICTATOR_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_DICTATOR_SNAPSHOT_DIR to render hub snapshots")
        }
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let model = AppModel(dictationHistoryURL: temp.appending(path: "h.json"),
                             fileTranscriptionHistoryURL: temp.appending(path: "f.json"))
        let snapshotWidth = max(900, min(1920, Double(ProcessInfo.processInfo.environment["TEST_RUNNER_DICTATOR_SNAPSHOT_WIDTH"] ?? "900") ?? 900))
        let screens: [(AppModel.Screen, String, AnyView)] = [
            (.dictation, "dictation", AnyView(DictationView())),
            (.transforms, "transforms", AnyView(TransformView())),
            (.files, "files", AnyView(FileTranscriptionView())),
            (.meetings, "meetings", AnyView(MeetingNotesView())),
            (.personalization, "personalization", AnyView(PersonalizationView())),
            (.style, "style", AnyView(StyleView())),
            (.insights, "insights", AnyView(InsightsView())),
            (.setup, "connect", AnyView(SetupView())),
            (.train, "train", AnyView(TrainView())),
            (.evaluate, "evaluate", AnyView(EvaluateView())),
            (.use, "silent-use", AnyView(UseView())),
            (.settings, "settings", AnyView(SettingsView())),
        ]
        for (destination, name, screen) in screens {
            model.screen = destination
            for scheme in [ColorScheme.light, .dark] {
                let view = screen
                    .environment(model)
                    .frame(width: snapshotWidth, height: 1400, alignment: .top)
                    .background(Theme.paper)
                    .environment(\.colorScheme, scheme)
                // A real (off-screen) window, so scroll views and AppKit controls draw.
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: snapshotWidth, height: 1400)
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
