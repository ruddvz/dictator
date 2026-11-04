import AppKit
import Carbon.HIToolbox
import XCTest
@testable import HushKey

final class OnboardingFlowTests: XCTestCase {
    // MARK: Steps

    func testStepsRunInOrderAndFinishAfterTheWhisper() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.step, .permissions)
        XCTAssertTrue(flow.isFirst)
        var seen: [OnboardingStep] = [flow.step]
        for _ in 1..<OnboardingStep.allCases.count {
            flow.advance()
            seen.append(flow.step)
        }
        XCTAssertEqual(seen, [.permissions, .micTest, .shortcut, .practice, .whisper])
        XCTAssertTrue(flow.isLast)
        XCTAssertFalse(flow.isFinished)
        flow.advance()
        XCTAssertTrue(flow.isFinished)
        XCTAssertEqual(flow.step, .whisper)
        flow.advance()
        XCTAssertEqual(flow.step, .whisper, "Nothing moves once finished")
    }

    func testEveryStepCanBeSkippedWithoutPassingIt() {
        var flow = OnboardingFlow()
        while !flow.isFinished {
            XCTAssertFalse(flow.currentStepPassed)
            XCTAssertTrue(flow.continueTitle.hasPrefix(flow.isLast ? "Finish" : "Skip"))
            flow.advance()
        }
        XCTAssertTrue(flow.completed.isEmpty)
    }

    func testContinueTitleFollowsTheStepsCheck() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.continueTitle, "Skip this step")
        flow.markPassed(.permissions)
        XCTAssertEqual(flow.continueTitle, "Continue")
        flow = OnboardingFlow(step: .whisper)
        XCTAssertEqual(flow.continueTitle, "Finish without it")
        flow.markPassed(.whisper)
        XCTAssertEqual(flow.continueTitle, "Finish")
    }

    func testBackStopsAtTheFirstStep() {
        var flow = OnboardingFlow(step: .micTest)
        flow.back()
        XCTAssertEqual(flow.step, .permissions)
        flow.back()
        XCTAssertEqual(flow.step, .permissions)
    }

    func testStepDotsOnlyJumpToStepsReachedOrPassed() {
        var flow = OnboardingFlow(step: .shortcut)
        flow.go(to: .whisper)
        XCTAssertEqual(flow.step, .shortcut, "Can't jump ahead past unreached steps")
        flow.go(to: .permissions)
        XCTAssertEqual(flow.step, .permissions)
        flow.markPassed(.practice)
        flow.go(to: .practice)
        XCTAssertEqual(flow.step, .practice)
    }

    func testProgressCountsTheCurrentStep() {
        XCTAssertEqual(OnboardingFlow().progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(OnboardingFlow(step: .whisper).progress, 1, accuracy: 0.0001)
    }

    // MARK: Remembering it

    private func freshDefaults() -> UserDefaults {
        let name = "OnboardingFlowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testShowsOnceOnFirstLaunchOnly() {
        let record = OnboardingRecord(defaults: freshDefaults())
        XCTAssertTrue(record.showsOnLaunch)
        record.record(.skipped)
        XCTAssertEqual(record.outcome, .skipped)
        XCTAssertFalse(record.showsOnLaunch, "Skipping still counts as shown")
    }

    func testFinishingAfterASkipIsRememberedAndNotUndoneBySkippingAgain() {
        let record = OnboardingRecord(defaults: freshDefaults())
        record.record(.skipped)
        record.record(.completed)
        XCTAssertEqual(record.outcome, .completed)
        record.record(.skipped)
        XCTAssertEqual(record.outcome, .completed)
    }

    func testSomeoneWhoAlreadyDictatedIsNotShownTheTourOnLaunch() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: OnboardingRecord.firstDictationKey)
        XCTAssertFalse(OnboardingRecord(defaults: defaults).showsOnLaunch)
    }

    func testCompletionUsesTheAppsSettingsKeys() {
        XCTAssertEqual(OnboardingRecord.outcomeKey, "onboardingOutcome")
        XCTAssertEqual(OnboardingRecord.firstDictationKey, "completedFirstDictation",
                       "Must match the key AppModel writes after the first dictation")
    }

    // MARK: Permission cards

    func testPermissionCardActions() {
        XCTAssertEqual(OnboardingPermission.microphone.action(for: .notAsked), .request)
        XCTAssertEqual(OnboardingPermission.microphone.action(for: .off), .openSettings)
        XCTAssertNil(OnboardingPermission.microphone.action(for: .granted))
        XCTAssertEqual(OnboardingPermission.accessibility.action(for: .off), .openSettings)
        XCTAssertEqual(OnboardingPermission.accessibility.action(for: .notAsked), .openSettings,
                       "Accessibility has no in-app prompt; it's always System Settings")
        XCTAssertNil(OnboardingPermission.accessibility.action(for: .granted))
        XCTAssertNil(OnboardingPermission.accessibility.buttonTitle(for: .granted))
        XCTAssertEqual(OnboardingPermission.microphone.buttonTitle(for: .notAsked), "Allow")
    }

    func testPermissionCardsOpenTheRightPanes() {
        XCTAssertEqual(OnboardingPermission.microphone.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertEqual(OnboardingPermission.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func testPermissionsPassOnlyWhenBothAreOn() {
        XCTAssertFalse(OnboardingPermission.allGranted([:]))
        XCTAssertFalse(OnboardingPermission.allGranted([.microphone: .granted, .accessibility: .off]))
        XCTAssertTrue(OnboardingPermission.allGranted([.microphone: .granted, .accessibility: .granted]))
    }

    // MARK: Mic test

    func testMicCheckNeedsSeveralLoudFramesNotOneBump() {
        var check = MicCheck()
        check.ingest(0.9)
        for _ in 0..<20 { check.ingest(0.02) }
        XCTAssertFalse(check.heardVoice)
        XCTAssertEqual(check.peak, 0.9, accuracy: 0.0001)
        for _ in 0..<MicCheck.framesNeeded { check.ingest(0.3) }
        XCTAssertTrue(check.heardVoice)
        check.reset()
        XCTAssertFalse(check.heardVoice)
        XCTAssertEqual(check.peak, 0)
    }

    // MARK: Shortcut keycaps

    func testFnShortcutIsOneCapLitByTheFunctionFlag() {
        let caps = ShortcutKeycaps(.fn)
        XCTAssertEqual(caps.caps.map(\.glyph), ["fn"])
        XCTAssertEqual(caps.lit(flags: [], keyDown: false), [])
        let lit = caps.lit(flags: .function, keyDown: false)
        XCTAssertEqual(lit, ["fn"])
        XCTAssertTrue(caps.isComplete(lit))
    }

    func testChordLightsEachCapAndCompletesOnlyWithAllHeld() {
        let caps = ShortcutKeycaps(DictationShortcut(KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.option, .shift])))
        XCTAssertEqual(caps.caps.map(\.glyph), ["⌥", "⇧", "D"])
        let optionOnly = caps.lit(flags: .option, keyDown: false)
        XCTAssertEqual(optionOnly, ["⌥"])
        XCTAssertFalse(caps.isComplete(optionOnly))
        let modifiers = caps.lit(flags: [.option, .shift], keyDown: false)
        XCTAssertFalse(caps.isComplete(modifiers))
        let all = caps.lit(flags: [.option, .shift], keyDown: true)
        XCTAssertEqual(all, ["⌥", "⇧", "D"])
        XCTAssertTrue(caps.isComplete(all))
        let controlShiftD = ShortcutKeycaps(DictationShortcut(KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.control, .shift])))
        XCTAssertEqual(controlShiftD.lit(flags: [.option, .shift], keyDown: true), ["⇧", "D"])
    }

    func testRecordedKeysStayWholeAndMouseButtonsHaveNoKeyCode() {
        let f5 = ShortcutKeycaps(DictationShortcut(KeyCombo(.key(UInt32(kVK_F5)), modifiers: [.command])))
        XCTAssertEqual(f5.caps.count, 2)
        XCTAssertEqual(f5.caps.first?.glyph, "⌘")
        XCTAssertEqual(f5.caps.last?.glyph, KeyCombo.keyName(for: UInt32(kVK_F5)))
        XCTAssertEqual(f5.keyCode, UInt16(kVK_F5))
        XCTAssertNil(ShortcutKeycaps(.fn).keyCode)
        if let mouse = KeyCombo(mouseButton: 3) {
            let caps = ShortcutKeycaps(DictationShortcut(mouse))
            XCTAssertEqual(caps.caps.count, 1)
            XCTAssertNil(caps.keyCode, "A mouse button must never light on a key with code 0")
            XCTAssertEqual(caps.lit(flags: [], keyDown: false), [])
        }
    }

    // MARK: Practice and whisper

    func testPracticePhraseCleansToWhatWasMeant() {
        XCTAssertEqual(CleanupPreview.clean(CleanupPreview.practicePhrase), "I'll be there at five.")
        XCTAssertEqual(CleanupPreview.clean("um, at four, no, five").lowercased(), "at five")
    }

    func testCleanupDiffMarksTheRemovedWords() {
        let words = CleanupPreview.words(raw: "Um, I'll be there at four, no, five.", cleaned: "I'll be there at five.")
        XCTAssertEqual(words.filter(\.removed).map(\.text), ["Um,", "four,", "no,"])
        XCTAssertEqual(words.filter { !$0.removed }.map(\.text), ["I'll", "be", "there", "at", "five."])
        XCTAssertTrue(CleanupPreview.words(raw: "Hello there.", cleaned: "Hello there.").allSatisfy { !$0.removed })
        XCTAssertEqual(CleanupPreview.words(raw: "", cleaned: "x"), [])
    }

    func testWhisperCheckAcceptsSmallMisheardings() {
        XCTAssertTrue(WhisperCheck.matches("A whisper is enough."))
        XCTAssertTrue(WhisperCheck.matches("whisper is enough"))
        XCTAssertFalse(WhisperCheck.matches("Hey, how's it going?"))
        XCTAssertFalse(WhisperCheck.matches("a sip is enough"), "The key word must come through")
    }

    func testWhisperLoudnessComparesWithTheSpeakingVoice() {
        XCTAssertEqual(WhisperCheck.relativeLoudness(whisperPeak: 0.1, speakingPeak: 0.4), 25)
        XCTAssertEqual(WhisperCheck.relativeLoudness(whisperPeak: 0.6, speakingPeak: 0.4), 100)
        XCTAssertNil(WhisperCheck.relativeLoudness(whisperPeak: 0.1, speakingPeak: 0))
        XCTAssertNil(WhisperCheck.relativeLoudness(whisperPeak: 0, speakingPeak: 0.4))
    }
}
