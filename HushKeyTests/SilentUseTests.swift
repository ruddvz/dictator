import AppKit
import Carbon.HIToolbox
import XCTest
@testable import HushKey

final class SilentUseTests: XCTestCase {
    private func samples(seconds: Double, rate: Double = 50, rotation: Double = 0.1) -> [MotionSample] {
        (0..<Int(seconds * rate)).map { MotionSample(t: Double($0) / rate, rotation: (rotation, 0, 0)) }
    }

    /// A mouthed-word stand-in: one rotation swing over the take, plus a little jitter.
    private func burst(seconds: Double = 0.8, rate: Double = 50, amplitude: Double) -> [MotionSample] {
        let count = Int(seconds * rate)
        return (0..<count).map { i in
            let phase = Double(i) / Double(count - 1)
            let jitter = Double.random(in: -0.002...0.002)
            return MotionSample(t: Double(i) / rate, rotation: (amplitude * sin(2 * .pi * phase) + jitter, jitter, jitter))
        }
    }

    private func evidence(templates: Int = 50, accuracy: Double = 0.6, pValue: Double = 0.01,
                          holdout: Double? = 0.5, holdoutChance: Double? = 0.3) -> Evaluation {
        Evaluation(labels: ["a", "b"], confusion: [[1, 0], [0, 1]], accuracy: accuracy, chance: 0.3,
                   permutationMean: 0.2, permutationP95: 0.35, pValue: pValue, permutations: 100,
                   templateCount: templates, sessionHoldoutAccuracy: holdout,
                   sessionHoldoutChance: holdoutChance, sessionHoldoutSessions: holdout == nil ? 0 : 2)
    }

    func testTakeIssueFlagsLengthAndHeadMovement() {
        XCTAssertNil(MotionFeatures.takeIssue(samples(seconds: 1)))
        XCTAssertEqual(MotionFeatures.takeIssue(samples(seconds: 0.2)), .tooShort)
        XCTAssertEqual(MotionFeatures.takeIssue(samples(seconds: 3.5)), .tooLong)
        XCTAssertEqual(MotionFeatures.takeIssue(samples(seconds: 1, rotation: 1.2)), .headMoved)
        XCTAssertEqual(MotionFeatures.takeIssue([]), .tooShort)
    }

    func testSmoothingKeepsLengthAndAveragesNeighbours() {
        let frames: [[Double]] = [[0], [3], [0], [0]]
        let smoothed = MotionFeatures.smoothed(frames, window: 3)
        XCTAssertEqual(smoothed.count, frames.count)
        XCTAssertEqual(smoothed[0][0], 1, accuracy: 1e-12) // edge frame repeats: (0 + 0 + 3) / 3
        XCTAssertEqual(smoothed[1][0], 1, accuracy: 1e-12)
        XCTAssertEqual(smoothed[2][0], 1, accuracy: 1e-12)
        XCTAssertEqual(smoothed[3][0], 0, accuracy: 1e-12)
        XCTAssertEqual(MotionFeatures.smoothed(frames, window: 1), frames)
    }

    func testRestWordIsRecognisedButNeverAccepted() throws {
        var templates: [Template] = []
        for _ in 0..<5 {
            templates.append(Template(label: "yes", samples: burst(amplitude: 0.15)))
            templates.append(Template(label: TemplateClassifier.restLabel, samples: burst(amplitude: 0)))
        }
        let classifier = try XCTUnwrap(TemplateClassifier(templates: templates, featureSet: .rotation))
        let still = classifier.predict(burst(amplitude: 0), maxDistance: 100, minConfidence: 0)
        XCTAssertEqual(still.best?.label, TemplateClassifier.restLabel)
        XCTAssertFalse(still.accepted)
    }

    func testEvidenceGateNeedsEveryCheck() {
        XCTAssertTrue(AppModel.evidenceUnlocksSilentUse(evidence()))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(nil))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(evidence(templates: 49)))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(evidence(accuracy: 0.3)))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(evidence(pValue: 0.06)))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(evidence(holdout: nil, holdoutChance: nil)))
        XCTAssertFalse(AppModel.evidenceUnlocksSilentUse(evidence(holdout: 0.3, holdoutChance: 0.3)))
    }

    @MainActor
    func testCancelledHoldEmitsNothing() {
        let capture = CaptureController()
        var received = 0
        capture.onSegment = { _ in received += 1 }
        capture.begin()
        for sample in samples(seconds: 0.5) { capture.ingest(sample) }
        capture.cancel()
        capture.end()
        XCTAssertEqual(received, 0)
        XCTAssertFalse(capture.isCapturing)
    }

    @MainActor
    func testControlKeyMonitorWatchesBothControlKeysAndTreatsFnAsAShortcut() {
        let control = FunctionKeyMonitor(key: .control)
        XCTAssertEqual(control.key.keyCodes, [UInt16(kVK_Control), UInt16(kVK_RightControl)])
        XCTAssertTrue(control.key.otherModifiers.contains(.function))
        XCTAssertFalse(control.key.otherModifiers.contains(.control))
        XCTAssertEqual(FunctionKeyMonitor().key.keyCodes, [UInt16(kVK_Function)])
    }

    func testControlGestureHoldsAndShortcutAborts() {
        var gesture = FunctionKeyGesture()
        XCTAssertEqual(gesture.fnDown(at: 0), .scheduleHoldStart)
        XCTAssertEqual(gesture.holdDelayElapsed(), .startHold)
        XCTAssertEqual(gesture.fnUp(at: 1), .endHold)

        XCTAssertEqual(gesture.fnDown(at: 2), .scheduleHoldStart)
        XCTAssertEqual(gesture.holdDelayElapsed(), .startHold)
        XCTAssertEqual(gesture.otherKeyDown(), .abortHold) // ⌃C while held
    }

    /// A quick Control hold used to be read as an fn-style tap and dropped without a word.
    func testControlGestureEndsQuickHoldsAndNeverGoesHandsFree() {
        var gesture = FunctionKeyGesture()
        gesture.supportsHandsFree = false
        XCTAssertEqual(gesture.fnDown(at: 0), .scheduleHoldStart)
        XCTAssertEqual(gesture.holdDelayElapsed(), .startHold)
        XCTAssertEqual(gesture.fnUp(at: 0.2), .endHold)
        XCTAssertEqual(gesture.fnDown(at: 0.3), .scheduleHoldStart)
        XCTAssertEqual(gesture.fnUp(at: 0.35), .cancelHoldStart) // released before the hold began
        XCTAssertFalse(gesture.isHandsFree)
    }

    @MainActor
    func testOnlyTheControlMonitorTreatsClicksAsShortcuts() {
        let control = FunctionKeyMonitor(key: .control).key
        XCTAssertTrue(control.watchedEvents.contains(.rightMouseDown))
        XCTAssertTrue(control.watchedEvents.contains(.leftMouseDown))
        XCTAssertFalse(control.supportsHandsFree)
        XCTAssertFalse(FunctionKeyMonitor().key.watchedEvents.contains(.leftMouseDown))
        XCTAssertTrue(FunctionKeyMonitor().key.supportsHandsFree)
    }

    @MainActor
    func testTooShortHoldIsReportedButCancelIsNot() {
        let capture = CaptureController()
        var tooShort = 0
        var segments = 0
        capture.onTooShort = { tooShort += 1 }
        capture.onSegment = { _ in segments += 1 }
        capture.begin()
        for sample in samples(seconds: 0.06) { capture.ingest(sample) }
        capture.end()
        XCTAssertEqual(tooShort, 1)
        capture.begin()
        capture.cancel()
        XCTAssertEqual(tooShort, 1)
        XCTAssertEqual(segments, 0)
    }

    func testCompleteSessionsNeedEnoughTakesOfEveryWord() {
        let first = UUID(), second = UUID()
        func takes(_ word: String, _ count: Int, _ session: UUID?, _ condition: SessionRecorder.Condition = .silent) -> [Template] {
            (0..<count).map { _ in Template(label: word, samples: [], condition: condition, sessionID: session) }
        }
        var templates = takes("yes", 3, first) + takes("no", 3, first)
        templates += takes("yes", 3, second) + takes("no", 2, second) + takes("no", 5, second, .normal)
        templates += takes("yes", 9, nil) + takes("no", 9, nil)
        XCTAssertEqual(AppModel.completeSessionCount(templates: templates, vocabulary: ["yes", "no"], condition: .silent), 1)
        templates += takes("no", 1, second)
        XCTAssertEqual(AppModel.completeSessionCount(templates: templates, vocabulary: ["yes", "no"], condition: .silent), 2)
        XCTAssertEqual(AppModel.completeSessionCount(templates: templates, vocabulary: [], condition: .silent), 0)
    }
}
