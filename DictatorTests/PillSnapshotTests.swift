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

    /// One sheet with every problem card the pill can show, for reviewing wording, wrapping and buttons.
    func testRenderNoticeCards() throws {
        guard let dir = (ProcessInfo.processInfo.environment["DICTATOR_SNAPSHOT_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_DICTATOR_SNAPSHOT_DIR"]) else {
            throw XCTSkip("Set DICTATOR_SNAPSHOT_DIR to write the notice-card sheet.")
        }
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let model = AppModel(dictationHistoryURL: temp.appending(path: "h.json"),
                             fileTranscriptionHistoryURL: temp.appending(path: "f.json"))
        let notices: [(String, DictationNotice?)] = [
            ("microphone", DictationRecovery.notice(audioError: "The microphone is being used by another app.", transcriberError: nil,
                                                    transcript: "", hasRetainedAudio: false)),
            ("recognition", DictationRecovery.notice(audioError: nil, transcriberError: "Speech recognition failed (error 203).",
                                                     transcript: "", hasRetainedAudio: true)),
            ("silent mic", DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "", hasRetainedAudio: false,
                                                    heardSound: false, microphoneName: "MacBook Pro Microphone")),
            ("nothing heard", DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "", hasRetainedAudio: true)),
            ("permission: microphone", DictationRecovery.permissionNeeded(.microphone)),
            ("permission: speech", DictationRecovery.permissionNeeded(.speechRecognition)),
            ("permission: accessibility", DictationRecovery.permissionNeeded(.accessibility)),
            ("cancelled", DictationRecovery.cancelled()),
            ("review", DictationRecovery.reviewBeforeInsertion(confidence: 0.4, peakLevel: 0.2)),
            ("couldn't type", DictationRecovery.insertionFailed("There is no text field selected.", canPasteAgain: true)),
            ("paste unconfirmed", DictationRecovery.pasteUnconfirmed("", canPasteAgain: true)),
            ("focus lost", DictationRecovery.focusLost(appName: "Slack")),
        ]
        let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(380), spacing: 16), count: 3), spacing: 24) {
            ForEach(Array(notices.enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 6) {
                    Text(entry.0).font(.caption).foregroundStyle(.white)
                    FloatingPillView(previewPhase: .error, previewNotice: entry.1).environment(model)
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.55))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
        else { return XCTFail("render notice sheet") }
        try png.write(to: URL(fileURLWithPath: dir).appending(path: "pill-notice-cards.png"))
    }
}
