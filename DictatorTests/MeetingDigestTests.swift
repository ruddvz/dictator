import XCTest
@testable import Dictator

final class MeetingDigestTests: XCTestCase {
    private let transcript = """
    Thanks everyone for joining the launch review. The launch date is still the twelfth of March. \
    Priya said the onboarding screens are finished and the copy is final. \
    The pricing page still needs the new annual plan. I'll send the updated pricing deck by Friday. \
    Marco, can you check the App Store screenshots before Wednesday? \
    We talked about the weather for a while. The launch review covered onboarding, pricing and screenshots. \
    Let's meet again next Tuesday to confirm the launch date.
    """

    func testClockFormatsMinutesAndHours() {
        XCTAssertEqual(MeetingDigest.clock(0), "0:00")
        XCTAssertEqual(MeetingDigest.clock(7.9), "0:07")
        XCTAssertEqual(MeetingDigest.clock(723), "12:03")
        XCTAssertEqual(MeetingDigest.clock(3723), "1:02:03")
        XCTAssertEqual(MeetingDigest.clock(-5), "0:00")
        XCTAssertEqual(MeetingDigest.clock(.infinity), "0:00")
    }

    func testLengthLabel() {
        XCTAssertEqual(MeetingDigest.lengthLabel(30), "Under a minute")
        XCTAssertEqual(MeetingDigest.lengthLabel(12 * 60 + 5), "12 min")
        XCTAssertEqual(MeetingDigest.lengthLabel(3600), "1 h")
        XCTAssertEqual(MeetingDigest.lengthLabel(3900), "1 h 5 min")
    }

    func testActionItemsParsesBulletsAndIgnoresNone() {
        XCTAssertEqual(MeetingDigest.actionItems(from: "No clear action items."), [])
        XCTAssertEqual(MeetingDigest.actionItems(from: ""), [])
        let parsed = MeetingDigest.actionItems(from: """
        Action items:
        - **Mira**: send the deck by Friday
        2. Marco checks screenshots
        * [ ] nothing
        • Book the room
        """)
        XCTAssertEqual(parsed, ["Mira: send the deck by Friday", "Marco checks screenshots", "[ ] nothing", "Book the room"])
    }

    func testFallbackActionItemsFindCommitmentsOnly() {
        let items = MeetingDigest.fallbackActionItems(from: transcript)
        XCTAssertTrue(items.contains("I'll send the updated pricing deck by Friday."))
        XCTAssertTrue(items.contains("Marco, can you check the App Store screenshots before Wednesday?"))
        XCTAssertTrue(items.contains { $0.hasPrefix("Let's meet again") })
        XCTAssertFalse(items.contains { $0.contains("weather") })
        XCTAssertLessThanOrEqual(items.count, MeetingDigest.maximumFallbackActionItems)
    }

    func testFallbackSummaryKeepsOrderAndSentenceCount() {
        let summary = MeetingDigest.fallbackSummary(from: transcript)
        let lines = summary.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, MeetingDigest.fallbackSummarySentences)
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("- ") })
        let sentences = MeetingDigest.sentences(in: transcript)
        let positions = lines.compactMap { line in sentences.firstIndex(of: String(line.dropFirst(2))) }
        XCTAssertEqual(positions.count, lines.count, "Fallback summary must quote the transcript verbatim")
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertFalse(summary.contains("weather"))
    }

    func testMarkdownHasSectionsAndCheckboxes() {
        let note = MeetingNote(createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: 125,
                               title: "Launch review", transcript: "Words said.",
                               summary: "- Launch is on track", actionItems: "- Send the deck\n- Check screenshots")
        let markdown = MeetingDigest.markdown(for: note)
        XCTAssertTrue(markdown.hasPrefix("# Launch review\n"))
        XCTAssertTrue(markdown.contains("## Summary\n\n- Launch is on track"))
        XCTAssertTrue(markdown.contains("## Action items\n\n- [ ] Send the deck\n- [ ] Check screenshots"))
        XCTAssertTrue(markdown.contains("## Transcript\n\nWords said."))
        XCTAssertTrue(markdown.contains("2 min"))

        let bare = MeetingNote(title: "Quick", transcript: "Hi.", actionItems: "No clear action items.")
        XCTAssertFalse(MeetingDigest.markdown(for: bare).contains("## Action items"))
        XCTAssertFalse(MeetingDigest.markdown(for: bare).contains("## Summary"))
    }

    func testFilenameIsSafe() {
        XCTAssertEqual(MeetingDigest.filename(for: "Meeting · 4 Nov 2026, 10:30"), "Meeting · 4 Nov 2026, 10-30.md")
        XCTAssertEqual(MeetingDigest.filename(for: "a/b\\c"), "a-b-c.md")
        XCTAssertEqual(MeetingDigest.filename(for: "  ..  "), "Meeting notes.md")
    }

    @MainActor
    func testDigestFillsEmptyFieldsWithoutAModelAndKeepsYourText() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MeetingDigestTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notesURL = directory.appending(path: "meeting-notes.json")
        let fresh = MeetingNote(title: "Launch", transcript: transcript)
        let edited = MeetingNote(title: "Edited", transcript: transcript, summary: "My own summary")
        let short = MeetingNote(title: "Short", transcript: "Hello, can you hear me?")
        try MeetingNotesStore.save([fresh, edited, short], to: notesURL)
        let service = MeetingNotesService(captureGate: AudioCaptureGate(), notesURL: notesURL,
                                          draftURL: directory.appending(path: "draft.json"))

        await service.digest(fresh.id)
        await service.digest(edited.id)
        await service.digest(short.id)

        let saved = try XCTUnwrap(MeetingNotesStore.load(from: notesURL))
        let digested = try XCTUnwrap(saved.first { $0.id == fresh.id })
        XCTAssertFalse(digested.summary.isEmpty)
        XCTAssertTrue(digested.actionItems.contains("I'll send the updated pricing deck by Friday."))
        XCTAssertTrue(service.fallbackDigestNoteIDs.contains(fresh.id))
        XCTAssertEqual(saved.first { $0.id == edited.id }?.summary, "My own summary")
        XCTAssertFalse(saved.first { $0.id == edited.id }?.actionItems.isEmpty ?? true)
        XCTAssertEqual(saved.first { $0.id == short.id }?.summary, "", "Too short to summarize")
        XCTAssertNil(service.digestingNoteID)
    }
}
