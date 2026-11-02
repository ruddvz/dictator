import XCTest
@testable import HushKey

final class PillMeterTests: XCTestCase {
    private let times: [TimeInterval] = stride(from: 0, to: 3, by: 0.07).map { $0 }

    func testSilenceRestsAsSmallDots() {
        for time in times {
            let heights = PillMeter.heights(count: 13, energy: 0, mode: .live, time: time)
            XCTAssertEqual(heights.count, 13)
            XCTAssertTrue(heights.allSatisfy { $0 >= PillMeter.restHeight && $0 <= PillMeter.restHeight + 0.05 })
        }
    }

    func testQuietSpeechIsClearlyVisible() {
        // A quarter of full speech should already lift the centre bar well above rest on average.
        let centres = times.map { PillMeter.heights(count: 13, energy: 0.25, mode: .live, time: $0)[6] }
        let mean = centres.reduce(0, +) / Double(centres.count)
        XCTAssertGreaterThan(mean, 0.45)
    }

    func testLoudSpeechStaysInBoundsAndCentreLeads() {
        var centre = 0.0, edge = 0.0
        for time in times {
            let heights = PillMeter.heights(count: 13, energy: 1, mode: .live, time: time)
            XCTAssertTrue(heights.allSatisfy { $0 <= 1 })
            centre += heights[6]
            edge += heights[0]
        }
        XCTAssertGreaterThan(centre, edge)
    }

    func testWorkingSweepMovesAcrossBars() {
        let early = PillMeter.heights(count: 13, energy: 0, mode: .working, time: 0.1)
        let later = PillMeter.heights(count: 13, energy: 0, mode: .working, time: 0.5)
        let peak = { (values: [Double]) in values.indices.max { values[$0] < values[$1] }! }
        XCTAssertLessThan(peak(early), peak(later))
        XCTAssertTrue((early + later).allSatisfy { $0 >= PillMeter.restHeight && $0 <= 1 })
    }
}
