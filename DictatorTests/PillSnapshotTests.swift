import SwiftUI
import XCTest
@testable import Dictator

/// Writes each pill phase to PNG when TEST_RUNNER_DICTATOR_SNAPSHOT_DIR is set, for reviewing spacing and icons.
/// Skipped otherwise, so the normal test run is unaffected.
@MainActor
final class PillSnapshotTests: XCTestCase {
    func testRenderPillPhases() throws {
        guard let dir = (ProcessInfo.processInfo.environment["DICTATOR_SNAPSHOT_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_DICTATOR_SNAPSHOT_DIR"]) else { throw XCTSkip("Set TEST_RUNNER_DICTATOR_SNAPSHOT_DIR to render pill snapshots") }
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let model = AppModel(dictationHistoryURL: temp.appending(path: "h.json"),
                             fileTranscriptionHistoryURL: temp.appending(path: "f.json"))
        var cases: [(String, FloatingPillView.Phase, Bool)] = FloatingPillView.Phase.allCases.map { ("\($0)", $0, true) }
        cases.append(("listening-held", .listening, false))
        for (name, phase, controls) in cases {
            let view = FloatingPillView(previewPhase: phase, previewShowsControls: controls)
                .environment(model)
                .padding(20)
                .background(Color(white: 0.55))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 4
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
            else { XCTFail("render \(name)"); continue }
            try png.write(to: URL(fileURLWithPath: dir).appending(path: "pill-\(name).png"))
        }
    }
}
