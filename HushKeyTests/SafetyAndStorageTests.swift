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

    func testDictationHistoryDeleteRemovesMalformedFileAndMissingFileIsSuccess() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-history-corrupt-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(DictationHistoryStore.containsFile(at: url))

        try DictationHistoryStore.delete(at: url)
        XCTAssertFalse(DictationHistoryStore.containsFile(at: url))
        try DictationHistoryStore.delete(at: url)
    }

    @MainActor
    func testAudioCaptureGatePreventsSimultaneousDictationAndMeetingCapture() {
        let gate = AudioCaptureGate()
        XCTAssertTrue(gate.claim(.dictation))
        XCTAssertFalse(gate.claim(.meeting))
        gate.release(.meeting)
        XCTAssertEqual(gate.owner, .dictation)
        gate.release(.dictation)
        XCTAssertNil(gate.owner)
        XCTAssertTrue(gate.claim(.meeting))
    }

    func testMeetingNotesRoundTripLocallyAndDeleteIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-meetings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let note = MeetingNote(title: "Planning", transcript: "We will ship Thursday.",
                               summary: "The team agreed on Thursday.", actionItems: "No clear action items.")

        try MeetingNotesStore.save([note], to: url)
        XCTAssertEqual(MeetingNotesStore.load(from: url), [note])
        try MeetingNotesStore.delete(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try MeetingNotesStore.delete(at: url)
    }

    func testMeetingTranscriptChunkerKeepsTextInBoundedOrderedChunks() {
        let source = String(repeating: "We agreed to review the local draft. ", count: 20)
        let chunks = LocalTransformService.meetingChunks(from: source, maxCharacters: 64)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 64 })
        XCTAssertEqual(chunks.joined(separator: " "), source.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @MainActor
    func testMeetingSummaryAndActionItemsRunWithLocalModelWhenAvailable() async throws {
        let transforms = LocalTransformService()
        guard transforms.modelIsAvailable else { throw XCTSkip("Apple's on-device model is unavailable on this Mac.") }
        let transcript = "The team approved the new draft. Mira will send the final copy by Thursday."

        let summary = try await transforms.summarizeMeeting(transcript)
        let actionItems = try await transforms.extractMeetingActionItems(transcript)

        XCTAssertFalse(summary.isEmpty)
        XCTAssertFalse(actionItems.isEmpty)
    }

    func testInsertionGateRejectsCaptureAndFinalization() {
        XCTAssertNotNil(DictationInsertionGate.blockedReason(
            audioIsRunning: true, recognitionIsRunning: false, isFinalizing: false))
        XCTAssertNotNil(DictationInsertionGate.blockedReason(
            audioIsRunning: false, recognitionIsRunning: true, isFinalizing: false))
        XCTAssertNotNil(DictationInsertionGate.blockedReason(
            audioIsRunning: false, recognitionIsRunning: false, isFinalizing: true))
        XCTAssertNil(DictationInsertionGate.blockedReason(
            audioIsRunning: false, recognitionIsRunning: false, isFinalizing: false))
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

    func testSpokenCorrectionsReplaceThePreviousPhraseAndKeepRawInputSeparate() {
        XCTAssertEqual(DictationBacktrack.apply(to: "Send it to Alice, actually Bob."), "Send it to Bob.")
        XCTAssertEqual(DictationBacktrack.apply(to: "Use the old route, scratch that, new route."), "Use the new route.")
        XCTAssertEqual(DictationBacktrack.apply(to: "I want to meet Tuesday, actually Thursday."), "I want to meet Thursday.")
        XCTAssertEqual(DictationBacktrack.apply(to: "Let's meet Friday afternoon, actually Thursday."),
                       "Let's meet Friday afternoon, actually Thursday.")
        XCTAssertEqual(DictationBacktrack.apply(to: "I like the first option."), "I like the first option.")
    }

    func testWritingModesFormatLineBreaksAndCodeTokens() {
        XCTAssertEqual(DictationModeFormatter.format("Hello new line team", mode: .message), "Hello\nteam")
        XCTAssertEqual(DictationModeFormatter.format("Hello new paragraph team", mode: .email), "Hello\n\nteam")
        XCTAssertEqual(DictationCodeFormatter.format("open parenthesis value close parenthesis"), "(value)")
        XCTAssertEqual(DictationTranscriptProcessor.process("log underscore value new line", mode: .code,
                                                             snippets: ""), "log_value")
    }

    func testOptionalCleanupRemovesOnlyStandaloneFillersAndKeepsRawRestorable() {
        XCTAssertEqual(DictationLocalCleanup.removeFillers(from: "Um, could you, uh, send it?"), "could you send it?")
        XCTAssertEqual(DictationLocalCleanup.removeFillers(from: "The umbrella is here."), "The umbrella is here.")
        XCTAssertEqual(DictationLocalCleanup.removeFillers(from: "ER is the emergency room."), "ER is the emergency room.")
        XCTAssertEqual(DictationTranscriptProcessor.process("Um, use foo underscore bar", mode: .code,
                                                             snippets: "", cleanupFillers: true), "use foo_bar")
    }

    func testSnippetValidationReportsMalformedLinesWithoutRejectingValidEntries() {
        let validation = DictationSnippetExpander.validation(for: "email => person@example.com\nbad line\nshort =>")
        XCTAssertEqual(validation.validCount, 1)
        XCTAssertEqual(validation.invalidLines, [2, 3])
        XCTAssertEqual(DictationSnippetExpander.expand(
            "Open C++ and message @name.",
            definitions: "C++ => C plus plus\n@name => Rudra"), "Open C plus plus and message Rudra.")
        let duplicateValidation = DictationSnippetExpander.validation(for: "C++ => C plus plus\nc++ => another expansion")
        XCTAssertEqual(duplicateValidation.validCount, 1)
        XCTAssertEqual(duplicateValidation.invalidLines, [2])
    }

    func testSubtitleExportsUseSRTAndWebVTTTimestamps() {
        let cues = [SubtitleCue(start: 1.25, duration: 0.8, text: "Hello."),
                    SubtitleCue(start: 61.1, duration: 1.2, text: "Goodbye.")]
        XCTAssertEqual(SubtitleFormatter.srt(cues),
                       "1\n00:00:01,250 --> 00:00:02,050\nHello.\n\n2\n00:01:01,100 --> 00:01:02,300\nGoodbye.\n")
        XCTAssertEqual(SubtitleFormatter.vtt(cues),
                       "WEBVTT\n\n00:00:01.250 --> 00:00:02.050\nHello.\n\n00:01:01.100 --> 00:01:02.300\nGoodbye.\n")
    }

    func testAutomaticModeMapsCommonMacAppsAndContextExtractionIsBounded() {
        XCTAssertEqual(DictationMode.resolved(.automatic, bundleIdentifier: "com.apple.mail"), .email)
        XCTAssertEqual(DictationMode.resolved(.automatic, bundleIdentifier: "com.todesktop.230313mzl4w4u92"), .natural)
        XCTAssertEqual(DictationMode.resolved(.automatic, bundleIdentifier: "com.microsoft.VSCode"), .code)
        let hints = DictationContextHintExtractor.extract(from: "Deploy AlphaWidget with build_v3 to project Redwood", limit: 2)
        XCTAssertEqual(hints.count, 2)
        XCTAssertTrue(hints.allSatisfy { ["AlphaWidget", "build_v3", "Redwood"].contains($0) })
    }

    func testDictationHistoryLoadsEntriesWithoutRawTranscriptField() throws {
        let data = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"text":"saved phrase"}]"#.utf8)
        let url = FileManager.default.temporaryDirectory.appending(path: "hushkey-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertEqual(DictationHistoryStore.load(from: url)?.first?.rawText, nil)
    }

    @MainActor
    func testDictationHistoryCanRestoreProcessedOrRawText() {
        let model = AppModel()
        let entry = DictationHistoryEntry(text: "Clean transcript.", rawText: "Um, clean transcript.")

        model.restoreDictation(entry)
        XCTAssertEqual(model.transcriber.text, "Clean transcript.")
        XCTAssertFalse(DictationHistorySaveGate.shouldSave(text: model.transcriber.text,
                                                            lastSavedText: model.lastSavedDictationText,
                                                            enabled: true))

        model.restoreDictation(entry, useRawText: true)
        XCTAssertEqual(model.transcriber.text, "Um, clean transcript.")
        model.restoreRawTranscript()
        XCTAssertEqual(model.transcriber.text, "Um, clean transcript.")
        XCTAssertFalse(DictationHistorySaveGate.shouldSave(text: model.transcriber.text,
                                                            lastSavedText: model.lastSavedDictationText,
                                                            enabled: true))
    }

    func testPersonalVocabularySplitsAndDeduplicatesLocalHints() {
        XCTAssertEqual(DictationVocabulary.terms(from: "HushKey, Maya\nhushkey\nCafé,cafe"),
                       ["HushKey", "Maya", "Café"])
        XCTAssertEqual(DictationVocabulary.encode([" Maya ", "", "HushKey"]), "Maya\nHushKey")
    }

    @MainActor
    func testLocalFillerTransformRunsWithoutTheLanguageModel() async throws {
        let service = LocalTransformService()
        let result = try await service.transform("Um, can you, uh, send it?", using: .removeFillers)
        XCTAssertEqual(result, "can you send it?")
        XCTAssertFalse(service.isTransforming)
    }

    @MainActor
    func testFoundationModelTransformRunsLocallyWhenAvailable() async throws {
        let service = LocalTransformService()
        guard service.modelIsAvailable else {
            throw XCTSkip("Apple's on-device language model is not available on this Mac.")
        }
        let result = try await service.transform("Please send me the meeting notes tomorrow.", using: .concise)
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(service.isTransforming)
    }

    @MainActor
    func testLocalTransformCanBeUndoneAndRejectsStalePreview() {
        let model = AppModel()
        let previousHistorySetting = model.savesDictationHistory
        model.savesDictationHistory = false
        defer { model.savesDictationHistory = previousHistorySetting }

        model.transcriber.replaceText("Please send this")
        XCTAssertFalse(model.applyLocalTransform("Please send this now.", basedOn: "Older transcript"))
        XCTAssertEqual(model.transcriber.text, "Please send this")

        XCTAssertTrue(model.applyLocalTransform("Please send this now.", basedOn: "Please send this"))
        XCTAssertEqual(model.transcriber.text, "Please send this now.")
        XCTAssertTrue(model.canUndoLocalTransform)

        model.undoLocalTransform()
        XCTAssertEqual(model.transcriber.text, "Please send this")
        XCTAssertFalse(model.canUndoLocalTransform)

        model.transcriber.replaceText(" Please send this \n")
        XCTAssertFalse(model.applyLocalTransform("Please send this", basedOn: " Please send this \n"))
        XCTAssertEqual(model.transcriber.text, " Please send this \n")
    }
}
