import XCTest
import SwiftUI
@testable import HushKey

final class BreathRibbonTests: XCTestCase {
    private let times: [TimeInterval] = stride(from: 0, to: 3, by: 0.07).map { $0 }
    private let count = 33
    private var centre: Int { count / 2 }

    func testSilenceRestsAsAThinLine() {
        for time in times {
            for mode: BreathRibbon.Mode in [.rest, .live] {
                let profile = BreathRibbon.profile(count: count, energy: 0, mode: mode, time: time)
                XCTAssertEqual(profile.count, count)
                XCTAssertTrue(profile.allSatisfy { $0 >= 0 && $0 <= BreathRibbon.restThickness * 1.2 })
            }
        }
    }

    func testWhisperVisiblyOpensTheLine() {
        // A whisper barely clears the envelope's gate; the ribbon should still more than double.
        let centres = times.map { BreathRibbon.profile(count: count, energy: 0.06, mode: .live, time: $0)[centre] }
        let mean = centres.reduce(0, +) / Double(centres.count)
        XCTAssertGreaterThan(mean, BreathRibbon.restThickness * 2)
    }

    func testQuietSpeechIsClearlyVisible() {
        let peaks = times.map { BreathRibbon.profile(count: count, energy: 0.25, mode: .live, time: $0).max() ?? 0 }
        let mean = peaks.reduce(0, +) / Double(peaks.count)
        XCTAssertGreaterThan(mean, 0.45)
    }

    func testLoudSpeechStaysInBoundsAndCentreLeads() {
        var middle = 0.0, edge = 0.0
        for time in times {
            let profile = BreathRibbon.profile(count: count, energy: 1, mode: .live, time: time)
            XCTAssertTrue(profile.allSatisfy { $0 <= 1 })
            middle += profile[centre]
            edge += profile[1]
        }
        XCTAssertGreaterThan(middle, edge)
    }

    func testWorkingBeadTravelsAlongTheLine() {
        let early = BreathRibbon.profile(count: count, energy: 0, mode: .working, time: 0.3)
        let later = BreathRibbon.profile(count: count, energy: 0, mode: .working, time: 0.7)
        let peak = { (values: [Double]) in values.indices.max { values[$0] < values[$1] }! }
        XCTAssertLessThan(peak(early), peak(later))
        XCTAssertTrue((early + later).allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

final class AmbientFieldTests: XCTestCase {
    private let size = CGSize(width: 770, height: 220)
    private let focus = UnitPoint(x: 0.78, y: 0.5)

    private func elementCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { _ in count += 1 }
        return count
    }

    private func points(_ path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            let n: Int = switch e.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            for i in 0..<n { result.append(e.points[i]) }
        }
        return result
    }

    func testRibbonKeyframesKeepTheirShapeSoCoreAnimationCanBlendThem() {
        // Path keyframes only interpolate when every frame has the same elements.
        for line in 0..<AmbientField.lineCount {
            let counts = stride(from: 0.0, to: AmbientField.ribbonLoop, by: 3.3).map {
                elementCount(AmbientField.line(line, in: size, focus: focus, time: $0))
            }
            XCTAssertEqual(Set(counts).count, 1)
        }
        let ribbon = Set(stride(from: 0.0, to: BreathRibbon.restLoop, by: 0.4).map {
            elementCount(BreathRibbon.path(in: CGSize(width: 230, height: 96), energy: 0, mode: .rest, time: $0).cgPath)
        })
        XCTAssertEqual(ribbon.count, 1)
    }

    func testLoopsEndWhereTheyStartSoTheyRepeatWithoutAJump() {
        for line in 0..<AmbientField.lineCount {
            let start = points(AmbientField.line(line, in: size, focus: focus, time: 0))
            let end = points(AmbientField.line(line, in: size, focus: focus, time: AmbientField.ribbonLoop))
            for (a, b) in zip(start, end) {
                XCTAssertEqual(a.x, b.x, accuracy: 0.01)
                XCTAssertEqual(a.y, b.y, accuracy: 0.01)
            }
        }
        let ribbonSize = CGSize(width: 230, height: 96)
        let start = points(BreathRibbon.path(in: ribbonSize, energy: 0, mode: .rest, time: 0).cgPath)
        let end = points(BreathRibbon.path(in: ribbonSize, energy: 0, mode: .rest, time: BreathRibbon.restLoop).cgPath)
        for (a, b) in zip(start, end) { XCTAssertEqual(a.y, b.y, accuracy: 0.01) }
    }
}
