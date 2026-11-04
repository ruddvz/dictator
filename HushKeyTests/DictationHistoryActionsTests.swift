import XCTest
@testable import HushKey

final class DictationHistoryActionsTests: XCTestCase {
    private func entries(_ texts: [String]) -> [DictationHistoryEntry] {
        texts.map { DictationHistoryEntry(text: $0) }
    }

    // MARK: Delete with Undo

    func testUndoPutsADeletedEntryBackWhereItWas() {
        let all = entries(["newest", "middle", "oldest"])
        let deleted = DeletedDictation(entry: all[1], index: 1)
        let restored = deleted.restoring(into: [all[0], all[2]])
        XCTAssertEqual(restored.map(\.text), ["newest", "middle", "oldest"])
    }

    func testUndoAfterNewDictationsKeepsTheOldPositionClampedAndTheLimit() {
        let all = entries(["a", "b"])
        let deleted = DeletedDictation(entry: all[1], index: 1)
        // A new dictation arrived during the Undo window.
        let fresh = DictationHistoryEntry(text: "fresh")
        XCTAssertEqual(deleted.restoring(into: [fresh, all[0]]).map(\.text), ["fresh", "b", "a"])
        // A stale index past the end lands at the end.
        let far = DeletedDictation(entry: all[1], index: 9)
        XCTAssertEqual(far.restoring(into: [all[0]]).map(\.text), ["a", "b"])
        // The history limit still holds.
        XCTAssertEqual(deleted.restoring(into: [fresh, all[0]], limit: 2).map(\.text), ["fresh", "b"])
    }

    func testUndoNeverDuplicatesAnEntryThatCameBack() {
        let all = entries(["a", "b"])
        let deleted = DeletedDictation(entry: all[0], index: 0)
        XCTAssertEqual(deleted.restoring(into: all).map(\.id), all.map(\.id))
    }

    @MainActor
    func testDeletingAHistoryEntryCanBeUndoneAndStaysSaved() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-history-undo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let historyURL = root.appending(path: "history.json")
        let seeded = entries(["first", "second", "third"])
        try DictationHistoryStore.save(seeded, to: historyURL)
        let model = AppModel(dictationHistoryURL: historyURL, fileTranscriptionHistoryURL: root.appending(path: "files.json"))

        model.deleteDictation(seeded[1])
        XCTAssertEqual(model.dictationHistory.map(\.text), ["first", "third"])
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.map(\.text), ["first", "third"],
                       "The deletion is saved straight away, not only when Undo expires")
        XCTAssertEqual(model.deletedDictation?.entry.id, seeded[1].id)

        model.undoDeleteDictation()
        XCTAssertNil(model.deletedDictation)
        XCTAssertEqual(model.dictationHistory.map(\.id), seeded.map(\.id))
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.map(\.id), seeded.map(\.id))

        // Deleting the only remaining entries removes the file; Undo brings it back.
        model.deleteDictation(seeded[0])
        model.deleteDictation(seeded[1])
        XCTAssertEqual(model.deletedDictation?.entry.id, seeded[1].id, "Only the latest deletion can be undone")
        model.deleteDictation(seeded[2])
        XCTAssertFalse(DictationHistoryStore.containsFile(at: historyURL))
        model.undoDeleteDictation()
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.map(\.text), ["third"])
    }

    @MainActor
    func testUndoWindowExpiresAndClearingHistoryForgetsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-history-expire-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let historyURL = root.appending(path: "history.json")
        let seeded = entries(["one", "two"])
        try DictationHistoryStore.save(seeded, to: historyURL)
        let model = AppModel(dictationHistoryURL: historyURL, fileTranscriptionHistoryURL: root.appending(path: "files.json"))

        model.deleteDictation(seeded[0])
        model.expireDeletedDictation(UUID())
        XCTAssertNotNil(model.deletedDictation, "Another entry's timer must not end this Undo")
        model.expireDeletedDictation(seeded[0].id)
        XCTAssertNil(model.deletedDictation)
        model.undoDeleteDictation()
        XCTAssertEqual(model.dictationHistory.map(\.text), ["two"])

        model.deleteDictation(seeded[1])
        model.clearDictationHistory()
        XCTAssertNil(model.deletedDictation)
        model.undoDeleteDictation()
        XCTAssertTrue(model.dictationHistory.isEmpty, "Delete all history can't be undone one entry at a time")
    }

    // MARK: Undo cleanup

    @MainActor
    func testUndoCleanupShowsTheOriginalAndCanBeRedone() throws {
        let entry = DictationHistoryEntry(text: "Let's meet at 3.", rawText: "um let's meet at three")
        let undone = try XCTUnwrap(entry.undoingCleanup())
        XCTAssertEqual(undone.text, "um let's meet at three")
        XCTAssertEqual(undone.cleanedText, "Let's meet at 3.")
        XCTAssertNil(undone.undoingCleanup(), "Undo can't stack")
        let redone = try XCTUnwrap(undone.redoingCleanup())
        XCTAssertEqual(redone.text, entry.text)
        XCTAssertNil(redone.cleanedText)

        XCTAssertNil(DictationHistoryEntry(text: "same").undoingCleanup())
        XCTAssertNil(DictationHistoryEntry(text: "same", rawText: "same").undoingCleanup())

        let root = FileManager.default.temporaryDirectory
            .appending(path: "hushkey-history-cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let historyURL = root.appending(path: "history.json")
        try DictationHistoryStore.save([entry], to: historyURL)
        let model = AppModel(dictationHistoryURL: historyURL, fileTranscriptionHistoryURL: root.appending(path: "files.json"))
        model.toggleCleanup(entry)
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.first?.text, "um let's meet at three")
        model.toggleCleanup(entry)
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.first?.text, "Let's meet at 3.")
    }

    // MARK: Meta line and storage

    func testMetaLineNamesTheAppDurationAndWords() {
        XCTAssertEqual(DictationHistoryEntry(text: "hello there friend", duration: 12.4, appName: "Slack").metaLine,
                       "Slack · 12 s · 3 words")
        XCTAssertEqual(DictationHistoryEntry(text: "one", duration: 75).metaLine, "1:15 · 1 word")
        XCTAssertEqual(DictationHistoryEntry(text: "two words").metaLine, "2 words")
    }

    func testOlderHistoryWithoutTheNewFieldsStillLoads() throws {
        let json = #"[{"id":"7A1C2A36-8D1B-4E0E-9E44-1D8D9F1C0A11","createdAt":0,"text":"old entry"}]"#
        let decoded = try JSONDecoder().decode([DictationHistoryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.text, "old entry")
        XCTAssertNil(decoded.first?.appName)
        XCTAssertNil(decoded.first?.cleanedText)
    }

    func testEditingAnEntryKeepsTheAppItWasDictatedInto() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "hushkey-upsert-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = DictationHistoryEntry(text: "draft", appName: "Mail")
        let edited = DictationHistoryEntry(id: original.id, text: "final draft")
        let saved = try DictationHistoryStore.upsertingAndSaving(edited, to: url, existing: [original])
        XCTAssertEqual(saved.first?.appName, "Mail")
        XCTAssertEqual(saved.first?.text, "final draft")
    }

    // MARK: Retry and Paste again states

    func testRetranscribeStates() {
        XCTAssertEqual(DictationRetranscribeGate.state(hasAudio: false, hadAudio: false, isBusy: false,
                                                       otherEngineProblem: nil), .hidden)
        XCTAssertEqual(DictationRetranscribeGate.state(hasAudio: false, hadAudio: true, isBusy: true,
                                                       otherEngineProblem: nil),
                       .unavailable("Audio no longer available"))
        XCTAssertEqual(DictationRetranscribeGate.state(hasAudio: true, hadAudio: false, isBusy: true,
                                                       otherEngineProblem: "Download Parakeet"),
                       .unavailable("Cannot retry while dictating"))
        XCTAssertEqual(DictationRetranscribeGate.state(hasAudio: true, hadAudio: false, isBusy: false,
                                                       otherEngineProblem: "Download Parakeet"),
                       .unavailable("Download Parakeet"))
        XCTAssertEqual(DictationRetranscribeGate.state(hasAudio: true, hadAudio: false, isBusy: false,
                                                       otherEngineProblem: nil), .available)
    }

    func testPasteAgainStates() {
        func state(latest: Bool = true, target: Bool = true, matches: Bool = true, busy: Bool = false,
                   inserted: Bool = false, enabled: Bool = true) -> DictationHistoryActionState {
            DictationHistoryPasteGate.state(isLatestDictation: latest, hasTarget: target, textMatches: matches,
                                            isBusy: busy, alreadyInserted: inserted, insertionEnabled: enabled)
        }
        XCTAssertEqual(state(), .available)
        XCTAssertEqual(state(latest: false), .hidden)
        XCTAssertEqual(state(target: false), .hidden)
        XCTAssertEqual(state(matches: false), .hidden, "An edited entry no longer matches what the field expects")
        XCTAssertEqual(state(busy: true), .unavailable("Cannot paste while dictating"))
        XCTAssertEqual(state(inserted: true), .unavailable("Already pasted once"))
        XCTAssertEqual(state(enabled: false), .unavailable("Text insertion is off"))
    }

    @MainActor
    func testEntriesWithoutKeptAudioOfferNoRetranscribe() {
        let model = AppModel(dictationHistoryURL: FileManager.default.temporaryDirectory
                                .appending(path: "hushkey-none-\(UUID().uuidString).json"),
                             fileTranscriptionHistoryURL: FileManager.default.temporaryDirectory
                                .appending(path: "hushkey-none-files-\(UUID().uuidString).json"))
        let entry = DictationHistoryEntry(text: "from an earlier session")
        XCTAssertEqual(model.retranscribeState(for: entry), .hidden)
        XCTAssertNil(model.retranscribeEngine(for: entry))
        XCTAssertEqual(model.pasteAgainState(for: entry), .hidden)
    }
}
