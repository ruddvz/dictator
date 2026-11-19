import SwiftUI
import XCTest
@testable import Dictator

/// Renders Home's voice band in every state to PNG when TEST_RUNNER_DICTATOR_SNAPSHOT_DIR is set, so the
/// motion can be reviewed frame by frame. Skipped otherwise.
@MainActor
final class MotionSnapshotTests: XCTestCase {
    func testRenderHomeBand() throws {
        guard let dir = ProcessInfo.processInfo.environment["TEST_RUNNER_DICTATOR_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_DICTATOR_SNAPSHOT_DIR to render the Home band")
        }
        let size = CGSize(width: 820, height: 172)
        let states: [(String, BreathRibbon.Mode, Float, Bool, String)] = [
            ("rest", .rest, 0, false, "Hold fn and talk."),
            ("hover", .rest, 0, true, "Hold fn and talk."),
            ("waiting", .waiting, 0, false, "Opening the microphone…"),
            ("whisper", .live, 0.4, false, "Listening."),
            ("live", .live, 0.75, false, "Listening."),
            ("working", .working, 0, false, "Writing it down…"),
        ]
        for (state, mode, level, inviting, line) in states {
            for scheme in [ColorScheme.light, .dark] {
                let band = ZStack(alignment: .leading) {
                    VoiceBandBackdrop(level: level, mode: mode, visible: true, inviting: inviting)
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        Text(line).font(.display(34)).tracking(-0.5).foregroundStyle(Theme.heroInk)
                        Text("In any app. Double-tap for hands-free. Nothing leaves this Mac.")
                            .font(.hkCallout).foregroundStyle(Theme.heroInk2)
                    }
                    .padding(.horizontal, Theme.s6)
                }
                .frame(width: size.width - 40, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                    .strokeBorder(Theme.heroInk.opacity(0.08), lineWidth: 1))
                .frame(width: size.width, height: size.height)
                .background(Theme.paper)
                .environment(\.colorScheme, scheme)
                try render(band, size: size, scheme: scheme,
                           to: URL(fileURLWithPath: dir).appending(path: "band-\(state)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    private func render(_ view: some View, size: CGSize, scheme: ColorScheme, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // Let the ribbons run a few frames so a live one has opened up.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return XCTFail("render") }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { return XCTFail("png") }
        try png.write(to: url)
    }
}
