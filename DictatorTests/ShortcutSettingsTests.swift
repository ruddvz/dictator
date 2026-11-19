import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Dictator

final class ShortcutParsingTests: XCTestCase {
    private let optionShiftD = KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.option, .shift])

    func testRawValueRoundTrips() {
        let combos: [KeyCombo] = [
            .functionKey,
            optionShiftD,
            KeyCombo(.key(UInt32(kVK_ANSI_V)), modifiers: [.control, .command]),
            KeyCombo(.key(UInt32(kVK_F5))),
            KeyCombo(.mouse(3)),
        ]
        for combo in combos {
            XCTAssertEqual(KeyCombo(rawValue: combo.rawValue), combo, combo.rawValue)
        }
        XCTAssertEqual(optionShiftD.rawValue, "opt+shift+k\(kVK_ANSI_D)")
        XCTAssertEqual(KeyCombo(.mouse(4)).rawValue, "m4")
    }

    func testMalformedRawValuesAreRejected() {
        for raw in ["", "k", "kx", "hyper+k2", "m1", "m0", "opt+shift", "k999", "opt+fn"] {
            XCTAssertNil(KeyCombo(rawValue: raw), raw)
        }
    }

    /// Settings saved by the old fixed menus must survive the move to the recorder.
    func testNamesSavedByTheOldMenusStillParse() {
        XCTAssertEqual(DictationShortcut(rawValue: "fn"), .fn)
        XCTAssertEqual(DictationShortcut(rawValue: "optionShiftD")?.label, "⌥⇧D")
        XCTAssertEqual(DictationShortcut(rawValue: "controlShiftD")?.carbonModifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(DictationShortcut(rawValue: "optionShiftReturn")?.label, "⌥⇧↩")
        XCTAssertEqual(InsertionShortcut(rawValue: "controlShiftI")?.keyCode, UInt32(kVK_ANSI_I))
        XCTAssertEqual(SelectedTextEditShortcut(rawValue: "controlShiftE")?.label, "⌃⇧E")
        XCTAssertEqual(CaptureShortcut(rawValue: "optionShiftM")?.keyCode, UInt16(kVK_ANSI_M))
        XCTAssertEqual(CaptureShortcut(rawValue: "controlShiftM")?.modifiers, [.control, .shift])
    }

    func testDefaultsMatchTheOldMenus() {
        XCTAssertEqual(DictationShortcut.default, .fn)
        XCTAssertTrue(DictationShortcut.default.usesFunctionKey)
        XCTAssertEqual(InsertionShortcut.default.label, "⌥⇧I")
        XCTAssertEqual(SelectedTextEditShortcut.default.label, "⌥⇧E")
        XCTAssertEqual(CaptureShortcut.default.label, "⌥⇧M")
        XCTAssertEqual(PasteLastShortcut.default.label, "⌃⌘V")
    }

    /// A saved value an action can't use falls back to its default instead of breaking it.
    func testStoredValueAnActionCannotUseIsRejected() {
        XCTAssertNil(SelectedTextEditShortcut(rawValue: "fn"))
        XCTAssertNil(CaptureShortcut(rawValue: "m3"))
        XCTAssertNotNil(PasteLastShortcut(rawValue: "m3"))
        XCTAssertNil(DictationShortcut(rawValue: "k\(kVK_ANSI_D)"))
    }

    func testLabelsUseMacModifierOrderAndWordKeys() {
        let all = KeyCombo(.key(UInt32(kVK_Return)), modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(all.label, "⌃⌥⇧⌘↩")
        XCTAssertEqual(KeyCombo(.key(UInt32(kVK_F5)), modifiers: .control).label, "⌃F5")
        XCTAssertEqual(KeyCombo(.key(UInt32(kVK_Space)), modifiers: .option).label, "⌥Space")
        XCTAssertEqual(KeyCombo(.mouse(3)).label, "Mouse 4")
        XCTAssertEqual(KeyCombo.functionKey.label, "fn")
        XCTAssertEqual(KeycapShortcut.keys(in: "⌃⌘F5"), ["⌃", "⌘", "F5"])
        XCTAssertEqual(KeycapShortcut.keys(in: "Mouse 4"), ["Mouse 4"])
        XCTAssertEqual(KeycapShortcut.keys(in: "⌥Space"), ["⌥", "Space"])
    }

    func testModifierFlagsConvertBothWays() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .function, .capsLock]
        let modifiers = KeyCombo.Modifiers(flags)
        XCTAssertEqual(modifiers, [.command, .option])
        XCTAssertEqual(modifiers.carbon, UInt32(cmdKey | optionKey))
        XCTAssertEqual(modifiers.eventFlags, [.command, .option])
    }

    func testFnAndMouseButtonsIgnoreModifiers() {
        XCTAssertEqual(KeyCombo(.functionKey, modifiers: .command).modifiers, [])
        XCTAssertEqual(KeyCombo(.mouse(3), modifiers: .shift).modifiers, [])
    }
}

final class ShortcutCaptureTests: XCTestCase {
    func testKeyWithModifiersIsCapturedOnKeyDown() {
        var capture = ShortcutCapture()
        XCTAssertEqual(capture.flagsChanged(keyCode: UInt16(kVK_Option), modifierFlags: .option), .listening)
        XCTAssertEqual(capture.keyDown(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.option, .shift]),
                       .captured(KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.option, .shift])))
    }

    func testFnAloneIsCapturedOnRelease() {
        var capture = ShortcutCapture()
        XCTAssertEqual(capture.flagsChanged(keyCode: UInt16(kVK_Function), modifierFlags: .function), .listening)
        XCTAssertEqual(capture.flagsChanged(keyCode: UInt16(kVK_Function), modifierFlags: []), .captured(.functionKey))
    }

    func testFnWithAnotherKeyRecordsThatKeyNotFn() {
        var capture = ShortcutCapture()
        _ = capture.flagsChanged(keyCode: UInt16(kVK_Function), modifierFlags: .function)
        XCTAssertEqual(capture.keyDown(keyCode: UInt16(kVK_F5), modifierFlags: .function),
                       .captured(KeyCombo(.key(UInt32(kVK_F5)))))
    }

    func testFnWithAModifierIsNotFnAlone() {
        var capture = ShortcutCapture()
        _ = capture.flagsChanged(keyCode: UInt16(kVK_Function), modifierFlags: .function)
        _ = capture.flagsChanged(keyCode: UInt16(kVK_Shift), modifierFlags: [.function, .shift])
        XCTAssertEqual(capture.flagsChanged(keyCode: UInt16(kVK_Function), modifierFlags: .shift), .listening)
    }

    func testEscapeCancelsButModifiedEscapeRecords() {
        var capture = ShortcutCapture()
        XCTAssertEqual(capture.keyDown(keyCode: UInt16(kVK_Escape), modifierFlags: []), .cancelled)
        XCTAssertEqual(capture.keyDown(keyCode: UInt16(kVK_Escape), modifierFlags: .control),
                       .captured(KeyCombo(.key(UInt32(kVK_Escape)), modifiers: .control)))
    }

    func testOnlyExtraMouseButtonsRecord() {
        var capture = ShortcutCapture()
        XCTAssertEqual(capture.mouseDown(button: 1), .listening)
        XCTAssertEqual(capture.mouseDown(button: 3), .captured(KeyCombo(.mouse(3))))
    }
}

@MainActor
final class ShortcutConflictTests: XCTestCase {
    private func key(_ code: Int, _ modifiers: KeyCombo.Modifiers) -> KeyCombo {
        KeyCombo(.key(UInt32(code)), modifiers: modifiers)
    }

    private var defaults: [ShortcutAction: KeyCombo] {
        [.dictation: .functionKey, .pasteLast: PasteLastShortcut.default.combo,
         .editSelection: SelectedTextEditShortcut.default.combo, .insertAgain: InsertionShortcut.default.combo,
         .undoInsertion: TextInsertionService.undoShortcut, .silentCapture: CaptureShortcut.default.combo]
    }

    func testFreeShortcutHasNoProblem() {
        XCTAssertNil(ShortcutConflicts.problem(with: key(kVK_ANSI_K, [.control, .option]), for: .dictation,
                                               assignments: defaults))
        XCTAssertNil(ShortcutConflicts.problem(with: key(kVK_F6, []), for: .pasteLast, assignments: defaults))
    }

    func testShortcutUsedByAnotherActionIsBlocked() {
        let problem = ShortcutConflicts.problem(with: InsertionShortcut.default.combo, for: .dictation,
                                                assignments: defaults)
        XCTAssertEqual(problem, .usedBy(.insertAgain))
        XCTAssertEqual(problem?.blocksSaving, true)
        XCTAssertEqual(ShortcutConflicts.problem(with: TextInsertionService.undoShortcut, for: .pasteLast,
                                                 assignments: defaults), .usedBy(.undoInsertion))
    }

    func testKeepingYourOwnShortcutIsNotAConflict() {
        XCTAssertNil(ShortcutConflicts.problem(with: PasteLastShortcut.default.combo, for: .pasteLast,
                                               assignments: defaults))
    }

    func testTurnedOffActionDoesNotConflict() {
        var assignments = defaults
        assignments[.pasteLast] = nil
        XCTAssertNil(ShortcutConflicts.problem(with: PasteLastShortcut.default.combo, for: .dictation,
                                               assignments: assignments))
    }

    func testEssentialMacShortcutsAreBlocked() {
        for combo in [key(kVK_ANSI_C, .command), key(kVK_ANSI_V, .command), key(kVK_ANSI_Q, .command),
                      key(kVK_Tab, .command), key(kVK_Space, .command)] {
            let problem = ShortcutConflicts.problem(with: combo, for: .dictation, assignments: defaults)
            guard case .reserved = problem else { return XCTFail("\(combo.label) should be reserved, got \(String(describing: problem))") }
            XCTAssertEqual(problem?.blocksSaving, true)
        }
    }

    func testCommonMacShortcutsWarnButSave() {
        let problem = ShortcutConflicts.problem(with: key(kVK_Space, .control), for: .dictation, assignments: defaults)
        guard case .warning = problem else { return XCTFail("expected a warning, got \(String(describing: problem))") }
        XCTAssertEqual(problem?.blocksSaving, false)
        let mouse = ShortcutConflicts.problem(with: KeyCombo(.mouse(3)), for: .dictation, assignments: defaults)
        XCTAssertEqual(mouse?.blocksSaving, false)
    }

    func testShortcutsThatWouldSwallowTypingAreInvalid() {
        for combo in [key(kVK_ANSI_D, []), key(kVK_ANSI_D, .shift), key(kVK_Return, []), key(kVK_Escape, [])] {
            guard case .invalid = ShortcutConflicts.problem(with: combo, for: .pasteLast, assignments: defaults) else {
                return XCTFail("\(combo.label) should be invalid")
            }
        }
    }

    func testFnAndMouseOnlyWhereSupported() {
        var assignments = defaults
        assignments[.dictation] = key(kVK_ANSI_D, [.option, .shift])
        XCTAssertNil(ShortcutConflicts.problem(with: .functionKey, for: .dictation, assignments: assignments))
        guard case .invalid = ShortcutConflicts.problem(with: .functionKey, for: .pasteLast, assignments: assignments),
              case .invalid = ShortcutConflicts.problem(with: KeyCombo(.mouse(3)), for: .silentCapture,
                                                         assignments: assignments) else {
            return XCTFail("fn and mouse buttons should be refused where they aren't wired")
        }
    }
}

final class HistoryRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(hoursAgo: Double) -> DictationHistoryEntry {
        DictationHistoryEntry(createdAt: now.addingTimeInterval(-hoursAgo * 3600), text: "\(hoursAgo) hours ago")
    }

    func testEachChoiceKeepsOnlyYoungEnoughEntries() {
        let entries = [entry(hoursAgo: 1), entry(hoursAgo: 23), entry(hoursAgo: 25),
                       entry(hoursAgo: 24 * 6), entry(hoursAgo: 24 * 8), entry(hoursAgo: 24 * 31)]
        XCTAssertEqual(DictationHistoryRetention.forever.pruning(entries, now: now), entries)
        XCTAssertEqual(DictationHistoryRetention.thirtyDays.pruning(entries, now: now), Array(entries.prefix(5)))
        XCTAssertEqual(DictationHistoryRetention.sevenDays.pruning(entries, now: now), Array(entries.prefix(4)))
        XCTAssertEqual(DictationHistoryRetention.oneDay.pruning(entries, now: now), Array(entries.prefix(2)))
    }

    func testEntryExactlyAtTheCutoffIsKeptAndFutureEntriesStay() {
        let entries = [entry(hoursAgo: 24), entry(hoursAgo: -5)]
        XCTAssertEqual(DictationHistoryRetention.oneDay.pruning(entries, now: now), entries)
    }

    func testUnknownStoredValueFallsBackToKeep() {
        XCTAssertEqual(DictationHistoryRetention(rawValue: "fortnight") ?? .default, .forever)
        XCTAssertEqual(DictationHistoryRetention.allCases.map(\.label), ["Keep", "30 days", "7 days", "24 hours"])
    }

    @MainActor
    func testModelPrunesTheSavedFileAndRemembersTheChoice() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "retention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = DictationHistoryRetention.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        let historyURL = directory.appending(path: "history.json")
        let fresh = DictationHistoryEntry(createdAt: Date().addingTimeInterval(-3600), text: "fresh")
        let stale = DictationHistoryEntry(createdAt: Date().addingTimeInterval(-3 * 86_400), text: "stale")
        try DictationHistoryStore.save([fresh, stale], to: historyURL)

        let model = AppModel(dictationHistoryURL: historyURL,
                             fileTranscriptionHistoryURL: directory.appending(path: "files.json"))
        XCTAssertEqual(model.dictationHistoryRetention, .forever)
        XCTAssertEqual(model.dictationHistory.count, 2)

        model.dictationHistoryRetention = .oneDay
        XCTAssertEqual(model.dictationHistory.map(\.text), ["fresh"])
        XCTAssertEqual(DictationHistoryStore.load(from: historyURL)?.map(\.text), ["fresh"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "oneDay")

        let relaunched = AppModel(dictationHistoryURL: historyURL,
                                  fileTranscriptionHistoryURL: directory.appending(path: "files.json"))
        XCTAssertEqual(relaunched.dictationHistoryRetention, .oneDay)

        relaunched.pruneDictationHistory(now: Date().addingTimeInterval(2 * 86_400))
        XCTAssertTrue(relaunched.dictationHistory.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }
}

final class ShortcutPersistenceTests: XCTestCase {
    @MainActor
    func testRecordedShortcutsPersistAndPasteLastCanBeTurnedOff() throws {
        let keys = [PasteLastShortcut.preferenceKey, DictationShortcut.preferenceKey]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { UserDefaults.standard.set(value, forKey: key) } }
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
        let directory = FileManager.default.temporaryDirectory.appending(path: "shortcuts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        func makeModel() -> AppModel {
            AppModel(dictationHistoryURL: directory.appending(path: "history.json"),
                     fileTranscriptionHistoryURL: directory.appending(path: "files.json"))
        }

        let model = makeModel()
        XCTAssertEqual(model.pasteLastShortcut, .default)
        XCTAssertEqual(model.dictationShortcut, .fn)
        let side = KeyCombo(.mouse(4))
        model.dictationShortcut = DictationShortcut(side)
        model.pasteLastShortcut = nil
        XCTAssertNil(model.shortcutAssignments[.pasteLast])
        XCTAssertEqual(model.shortcutAssignments[.dictation], side)

        let relaunched = makeModel()
        XCTAssertNil(relaunched.pasteLastShortcut)
        XCTAssertEqual(relaunched.dictationShortcut.mouseButton, 4)
        XCTAssertEqual(relaunched.dictationShortcut.label, "Mouse 5")
    }
}
