import XCTest
@testable import HushKey

final class DictationCueTests: XCTestCase {
    func testCuesAreShortQuietAndClickFree() {
        for cue in DictationCue.allCases {
            let samples = cue.samples
            let seconds = Double(samples.count) / DictationCue.sampleRate
            XCTAssertGreaterThan(seconds, 0.1, "\(cue)")
            XCTAssertLessThan(seconds, 0.4, "\(cue) should stay out of the way")
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.05, "\(cue) should be audible")
            XCTAssertLessThan(peak, 0.6, "\(cue) should stay soft")
            XCTAssertLessThan(abs(samples.first ?? 1), 0.01, "\(cue) starts without a click")
            XCTAssertLessThan(abs(samples.last ?? 1), 0.01, "\(cue) ends without a click")
        }
    }

    func testCuesSoundDifferent() {
        XCTAssertNotEqual(DictationCue.start.samples, DictationCue.success.samples)
        XCTAssertNotEqual(DictationCue.success.samples, DictationCue.error.samples)
    }

    func testWavHeaderDescribesSixteenBitMono() {
        let data = DictationCue.success.wavData
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(data.count, 44 + DictationCue.success.samples.count * 2)
    }
}
