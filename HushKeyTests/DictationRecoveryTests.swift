import AVFoundation
import XCTest
@testable import HushKey

final class DictationRecoveryTests: XCTestCase {
    func testMicrophoneErrorCannotRetry() {
        let notice = DictationRecovery.notice(audioError: "Microphone access denied.", transcriberError: nil,
                                              transcript: "", hasRetainedAudio: true)
        XCTAssertEqual(notice?.kind, .microphone)
        XCTAssertEqual(notice?.canRetry, false)
        XCTAssertEqual(notice?.detail, "Microphone access denied.")
    }

    func testTranscriptWinsOverStaleRecognitionError() {
        XCTAssertNil(DictationRecovery.notice(audioError: nil, transcriberError: "Speech recognition issue: x",
                                              transcript: "hello there", hasRetainedAudio: true))
    }

    func testRecognitionErrorOffersRetryOnlyWithRetainedAudio() {
        let withAudio = DictationRecovery.notice(audioError: nil, transcriberError: "Speech recognition issue: x",
                                                 transcript: "  ", hasRetainedAudio: true)
        XCTAssertEqual(withAudio?.kind, .recognition)
        XCTAssertEqual(withAudio?.canRetry, true)
        XCTAssertEqual(withAudio?.canPasteAgain, false)

        let withoutAudio = DictationRecovery.notice(audioError: nil, transcriberError: "Not authorized.",
                                                    transcript: "", hasRetainedAudio: false)
        XCTAssertEqual(withoutAudio?.canRetry, false)
    }

    func testEmptyTranscriptIsNothingHeard() {
        let notice = DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "\n",
                                              hasRetainedAudio: true)
        XCTAssertEqual(notice?.kind, .nothingHeard)
        XCTAssertEqual(notice?.canRetry, true)
    }

    func testSilentMicrophoneIsBlamedOnTheInput() {
        let notice = DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "",
                                              hasRetainedAudio: true, heardSound: false, microphoneName: "AirPods")
        XCTAssertEqual(notice?.kind, .silentMicrophone)
        XCTAssertEqual(notice?.message, "We couldn't hear you")
        XCTAssertEqual(notice?.canRetry, false)
        XCTAssertEqual(notice?.offersMicrophoneHelp, true)
        XCTAssertTrue(notice?.detail.contains("AirPods") == true)
    }

    func testSoundThatWasNotSpeechIsStillNothingHeard() {
        let notice = DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "",
                                              hasRetainedAudio: true, heardSound: true)
        XCTAssertEqual(notice?.kind, .nothingHeard)
        XCTAssertEqual(notice?.offersMicrophoneHelp, false)
    }

    func testTextWinsOverASilentPeak() {
        XCTAssertNil(DictationRecovery.notice(audioError: nil, transcriberError: nil, transcript: "hi",
                                              hasRetainedAudio: true, heardSound: false))
    }

    func testMicrophoneThatDidNotStartOffersHelp() {
        let notice = DictationRecovery.notice(audioError: "Input device has no usable format.", transcriberError: nil,
                                              transcript: "", hasRetainedAudio: false)
        XCTAssertEqual(notice?.offersMicrophoneHelp, true)
    }

    func testCancelledNoticeIsNeutralAndOffersUndo() {
        let notice = DictationRecovery.cancelled()
        XCTAssertEqual(notice.kind, .cancelled)
        XCTAssertTrue(notice.isNeutral)
        XCTAssertTrue(notice.canRetry)
        XCTAssertFalse(notice.offersMicrophoneHelp)
        XCTAssertFalse(DictationRecovery.notice(audioError: "x", transcriberError: nil, transcript: "",
                                                hasRetainedAudio: false)!.isNeutral)
    }

    func testInsertionAndFocusNoticesOfferPasteAgain() {
        let failed = DictationRecovery.insertionFailed("Focus changed before insertion. Nothing was inserted.",
                                                       canPasteAgain: true)
        XCTAssertEqual(failed.kind, .insertion)
        XCTAssertTrue(failed.canPasteAgain)
        XCTAssertFalse(failed.canRetry)
        XCTAssertTrue(failed.detail.hasPrefix("Focus changed"))

        let lost = DictationRecovery.focusLost(appName: "Notes")
        XCTAssertEqual(lost.kind, .focusLost)
        XCTAssertEqual(lost.message, "Click back into Notes")
        XCTAssertTrue(lost.canPasteAgain)
    }

    func testUnconfirmedPasteWarnsBeforeExplicitRetry() {
        let notice = DictationRecovery.pasteUnconfirmed(
            "Paste was sent, but the field did not confirm it.", canPasteAgain: true)

        XCTAssertEqual(notice.message, "Check the field first")
        XCTAssertTrue(notice.detail.contains("Check the destination before retrying"))
        XCTAssertTrue(notice.detail.contains("transcript is saved in HushKey"))
        XCTAssertTrue(notice.canPasteAgain)
        XCTAssertFalse(notice.canRetry)
    }

    func testPasteAgainRequiresOriginalAppAndField() {
        func decide(frontmost: Bool, field: Bool) -> PasteAgainGate.Decision {
            PasteAgainGate.decision(text: "hi", hasTarget: true, isBusy: false, alreadyInserted: false, insertionEnabled: true,
                                    targetIsFrontmost: frontmost, targetFieldIsFocused: field)
        }
        XCTAssertEqual(decide(frontmost: true, field: true), .allowed)
        XCTAssertEqual(decide(frontmost: false, field: false), .focusLost)
        XCTAssertEqual(decide(frontmost: true, field: false), .focusLost)
    }

    func testPasteAgainRefusesWithoutTextTargetOrInsertion() {
        XCTAssertNotEqual(PasteAgainGate.decision(text: " ", hasTarget: true, isBusy: false, alreadyInserted: false, insertionEnabled: true,
                                                  targetIsFrontmost: true, targetFieldIsFocused: true), .allowed)
        XCTAssertNotEqual(PasteAgainGate.decision(text: "hi", hasTarget: false, isBusy: false, alreadyInserted: false, insertionEnabled: true,
                                                  targetIsFrontmost: true, targetFieldIsFocused: true), .allowed)
        XCTAssertNotEqual(PasteAgainGate.decision(text: "hi", hasTarget: true, isBusy: false, alreadyInserted: false, insertionEnabled: false,
                                                  targetIsFrontmost: true, targetFieldIsFocused: true), .allowed)
        XCTAssertEqual(PasteAgainGate.decision(text: "hi", hasTarget: true, isBusy: false, alreadyInserted: true,
                                               insertionEnabled: true, targetIsFrontmost: true,
                                               targetFieldIsFocused: true),
                       .unavailable("This dictation was already typed once."))
        XCTAssertNotEqual(PasteAgainGate.decision(text: "hi", hasTarget: true, isBusy: true, alreadyInserted: false, insertionEnabled: true,
                                                  targetIsFrontmost: true, targetFieldIsFocused: true), .allowed)
    }

    func testRetainedAudioCopiesBuffersAndResets() throws {
        let audio = RetainedDictationAudio()
        XCTAssertFalse(audio.isUsable)
        let buffer = try makeBuffer(seconds: 0.5, value: 0.25)
        audio.append(buffer)
        buffer.floatChannelData![0][0] = 0.9 // the engine reuses tap buffers
        XCTAssertTrue(audio.isUsable)
        XCTAssertEqual(audio.duration, 0.5, accuracy: 0.001)
        let kept = audio.snapshot()
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].floatChannelData![0][0], 0.25)
        audio.reset()
        XCTAssertFalse(audio.isUsable)
        XCTAssertTrue(audio.snapshot().isEmpty)
    }

    func testRetainedAudioDropsEverythingPastTheCap() throws {
        XCTAssertTrue(RetainedDictationAudio.accepts(currentSeconds: 299, adding: 1, overflowed: false))
        XCTAssertFalse(RetainedDictationAudio.accepts(currentSeconds: 299.5, adding: 1, overflowed: false))
        XCTAssertFalse(RetainedDictationAudio.accepts(currentSeconds: 0, adding: 1, overflowed: true))

        let audio = RetainedDictationAudio()
        let chunk = try makeBuffer(seconds: 100, value: 0)
        for _ in 0..<3 { audio.append(chunk) }
        XCTAssertTrue(audio.isUsable)
        audio.append(try makeBuffer(seconds: 1, value: 0))
        XCTAssertFalse(audio.isUsable)
        XCTAssertTrue(audio.snapshot().isEmpty)
        audio.reset()
        audio.append(try makeBuffer(seconds: 1, value: 0))
        XCTAssertTrue(audio.isUsable)
    }

    func testTranscriptCardLiveStates() {
        XCTAssertEqual(TranscriptCard.state(isCapturing: true, hasTarget: false, transcript: "",
                                            isCollapsed: false, keepsFinishedText: false),
                       .live(hint: TranscriptCard.noTargetHint))
        XCTAssertEqual(TranscriptCard.state(isCapturing: true, hasTarget: true, transcript: " ",
                                            isCollapsed: false, keepsFinishedText: false), .hidden)
        XCTAssertEqual(TranscriptCard.state(isCapturing: true, hasTarget: true, transcript: "hello",
                                            isCollapsed: false, keepsFinishedText: false), .hidden)
        XCTAssertEqual(TranscriptCard.state(isCapturing: true, hasTarget: false, transcript: "hello",
                                            isCollapsed: true, keepsFinishedText: false), .hidden)
    }

    func testTranscriptCardStaysUpOnlyWithoutATarget() {
        XCTAssertEqual(TranscriptCard.state(isCapturing: false, hasTarget: false, transcript: "hello",
                                            isCollapsed: true, keepsFinishedText: true),
                       .finished(hint: TranscriptCard.noTargetHint))
        XCTAssertEqual(TranscriptCard.state(isCapturing: false, hasTarget: true, transcript: "hello",
                                            isCollapsed: false, keepsFinishedText: false), .hidden)
        XCTAssertEqual(TranscriptCard.state(isCapturing: false, hasTarget: false, transcript: "",
                                            isCollapsed: false, keepsFinishedText: true), .hidden)
        // Typing into the field failed: the card comes back so the text can be copied.
        XCTAssertEqual(TranscriptCard.state(isCapturing: false, hasTarget: true, transcript: "hello",
                                            isCollapsed: false, keepsFinishedText: true),
                       .finished(hint: TranscriptCard.notTypedHint))
    }

    func testTranscriptTailKeepsTheEndAtAWordBoundary() {
        XCTAssertEqual(TranscriptCard.tail("  short text \n"), "short text")
        let long = (1...40).map { "word\($0)" }.joined(separator: " ")
        let tail = TranscriptCard.tail(long, maxCharacters: 30)
        XCTAssertTrue(tail.hasPrefix("…word"))
        XCTAssertTrue(tail.hasSuffix("word40"))
        XCTAssertLessThanOrEqual(tail.count, 31)
        XCTAssertEqual(TranscriptCard.tail(String(repeating: "a", count: 50), maxCharacters: 10),
                       "…" + String(repeating: "a", count: 10))
    }

    private func makeBuffer(seconds: Double, value: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = value }
        return buffer
    }

    func testPermissionNoticesNameTheSwitchAndOpenItsPane() {
        let mic = DictationRecovery.permissionNeeded(.microphone)
        XCTAssertEqual(mic.missingPermission, .microphone)
        XCTAssertFalse(mic.canRetry)
        XCTAssertTrue(mic.detail.contains("Microphone"))
        XCTAssertEqual(mic.missingPermission?.settingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        let speech = DictationRecovery.permissionNeeded(.speechRecognition)
        XCTAssertEqual(speech.message, "Allow speech recognition")
        XCTAssertTrue(speech.missingPermission?.settingsURL?.absoluteString.hasSuffix("Privacy_SpeechRecognition") == true)
        XCTAssertNil(DictationRecovery.cancelled().missingPermission)
    }
}
