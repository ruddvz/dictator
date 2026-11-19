import XCTest
@testable import Dictator

final class SpeechEnvelopeTests: XCTestCase {
    /// Simulates a level stream at `rate` Hz and returns the last amount.
    private func run(_ envelope: inout SpeechEnvelope, level: Float, seconds: Double,
                     from start: Double, rate: Double = 30) -> Float {
        var amount: Float = 0
        var time = start
        while time < start + seconds {
            amount = envelope.amount(for: level, at: time)
            time += 1 / rate
        }
        return amount
    }

    func testQuietRoomStaysFlat() {
        var envelope = SpeechEnvelope()
        XCTAssertEqual(run(&envelope, level: 0.2, seconds: 5, from: 0), 0)
    }

    func testSteadyNoiseAboveDefaultIsLearnedNotShownAsSpeech() {
        var envelope = SpeechEnvelope()
        _ = run(&envelope, level: 0.1, seconds: 0.5, from: 0)       // a quiet moment sets the floor
        XCTAssertEqual(run(&envelope, level: 0.12, seconds: 3, from: 0.5), 0)
    }

    func testSpeechAfterSilenceMoves() {
        var envelope = SpeechEnvelope()
        _ = run(&envelope, level: 0.15, seconds: 1, from: 0)
        XCTAssertGreaterThan(run(&envelope, level: 0.6, seconds: 0.2, from: 1), 0.8)
    }

    func testLongSentenceKeepsMoving() {
        var envelope = SpeechEnvelope()
        _ = run(&envelope, level: 0.15, seconds: 1, from: 0)
        // Ten seconds of continuous speech: the floor may rise only 0.2, so it still reads as speech.
        XCTAssertGreaterThan(run(&envelope, level: 0.6, seconds: 10, from: 1), 0.4)
    }

    func testFirstSampleDuringSpeechIsNotTakenAsFloor() {
        var envelope = SpeechEnvelope()
        XCTAssertGreaterThan(envelope.amount(for: 0.7, at: 0), 0.9)
    }

    func testSameResultWhateverTheReportingRate() {
        var slow = SpeechEnvelope(), fast = SpeechEnvelope()
        _ = run(&slow, level: 0.15, seconds: 1, from: 0, rate: 10)
        _ = run(&fast, level: 0.15, seconds: 1, from: 0, rate: 100)
        let a = run(&slow, level: 0.55, seconds: 4, from: 1, rate: 10)
        let b = run(&fast, level: 0.55, seconds: 4, from: 1, rate: 100)
        XCTAssertEqual(a, b, accuracy: 0.03)
    }
}
