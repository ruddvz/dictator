import XCTest
@testable import HushKey

final class SafetyAndStorageTests: XCTestCase {
    @MainActor
    func testHoldCaptureEmitsOneSegmentOnRelease() {
        let capture = CaptureController()
        var received: [[MotionSample]] = []
        capture.onSegment = { received.append($0) }
        capture.begin()
        for index in 0..<8 {
            capture.ingest(MotionSample(t: Double(index) * 0.05, rotation: (0.1, 0, 0)))
        }
        capture.end()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].count, 8)
        XCTAssertFalse(capture.isCapturing)
    }

    @MainActor
    func testTooShortCaptureIsRejected() {
        let capture = CaptureController()
        var received = 0
        capture.onSegment = { _ in received += 1 }
        capture.begin()
        for index in 0..<3 {
            capture.ingest(MotionSample(t: Double(index) * 0.03, rotation: (0, 0, 0)))
        }
        capture.end()
        XCTAssertEqual(received, 0)
    }

    @MainActor
    func testPermissionAndConnectionStatesFailClosed() {
        XCTAssertEqual(HeadphoneMotionService.startupStatus(isAvailable: false, authorization: .authorized), .unsupported)
        XCTAssertEqual(HeadphoneMotionService.startupStatus(isAvailable: true, authorization: .denied), .denied)
        XCTAssertEqual(HeadphoneMotionService.startupStatus(isAvailable: true, authorization: .restricted), .denied)
        XCTAssertEqual(HeadphoneMotionService.startupStatus(isAvailable: true, authorization: .notDetermined), .waiting)

        let motion = HeadphoneMotionService()
        motion.connectionChanged(true)
        XCTAssertTrue(motion.isConnected)
        motion.connectionChanged(false)
        XCTAssertFalse(motion.isConnected)
        XCTAssertEqual(motion.status, .waiting)
    }

    @MainActor
    func testInsertionTargetWhitelistRejectsSecureAndNonTextControls() {
        XCTAssertTrue(TextInsertionService.isSupportedTextTarget(role: "AXTextField", subrole: ""))
        XCTAssertTrue(TextInsertionService.isSupportedTextTarget(role: "AXTextArea", subrole: ""))
        XCTAssertFalse(TextInsertionService.isSupportedTextTarget(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(TextInsertionService.isSupportedTextTarget(role: "AXButton", subrole: ""))
    }

    func testDatasetRoundTripsLocallyWithConditionAndSessionMetadata() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let sessionID = UUID()
        let template = Template(label: "yes", samples: [MotionSample(t: 0)],
                                condition: .silent, sessionID: sessionID)
        let dataset = Dataset(vocabulary: ["yes"], templates: [template])
        try TemplateStore.save(dataset, to: url)
        let restored = try XCTUnwrap(TemplateStore.load(from: url))
        XCTAssertEqual(restored.vocabulary, ["yes"])
        XCTAssertEqual(restored.templates.first?.condition, .silent)
        XCTAssertEqual(restored.templates.first?.sessionID, sessionID)
    }

    func testDictationHistoryRoundTripsLocally() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [DictationHistoryEntry(text: "A local phrase."), DictationHistoryEntry(text: "Another phrase.")]

        try DictationHistoryStore.save(entries, to: url)

        XCTAssertEqual(DictationHistoryStore.load(from: url), entries)
    }

    @MainActor
    func testDictationIsTheFirstScreen() {
        let model = AppModel()
        XCTAssertEqual(model.screen, .dictation)
        XCTAssertFalse(model.audio.isRunning)
    }

    func testLocalVoiceSnippetsExpandWholeCues() {
        let result = DictationSnippetExpander.expand(
            "Send my short intro, please.",
            definitions: "short intro => Hello team, my name is Rudra.")
        XCTAssertEqual(result, "Send my Hello team, my name is Rudra, please.")
    }
}
