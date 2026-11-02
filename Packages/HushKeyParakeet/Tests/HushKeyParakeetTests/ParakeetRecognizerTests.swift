import AVFoundation
import XCTest
@testable import HushKeyParakeet

final class ParakeetRecognizerTests: XCTestCase {
    func testSamplesJoinBuffersAndResampleTo16kMono() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffers = try (0..<3).map { _ in try Self.tone(format: format, frames: 4_800) }
        let samples = try ParakeetRecognizer.samples(from: buffers)
        // 0.3 s at 48 kHz becomes about 0.3 s at 16 kHz.
        XCTAssertEqual(Double(samples.count), 4_800, accuracy: 64)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1)
    }

    func testSamplesSkipBuffersInAnotherFormat() throws {
        let mono = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let other = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let samples = try ParakeetRecognizer.samples(from: [
            try Self.tone(format: mono, frames: 1_600), try Self.tone(format: other, frames: 4_410)])
        XCTAssertEqual(samples.count, 1_600)
    }

    func testSamplesOfNothingIsEmpty() throws {
        XCTAssertEqual(try ParakeetRecognizer.samples(from: []), [])
    }

    func testModelFoldersMatchFluidAudioLayout() {
        let root = URL(fileURLWithPath: "/tmp/models")
        XCTAssertEqual(ParakeetModel.englishV2.directory(in: root).lastPathComponent, "parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ParakeetModel.multilingualV3.directory(in: root).lastPathComponent, "parakeet-tdt-0.6b-v3")
        XCTAssertFalse(ParakeetModel.englishV2.isDownloaded(in: root.appending(path: UUID().uuidString)))
    }

    func testTranscribeBeforeLoadingFails() async {
        do {
            _ = try await ParakeetRecognizer().transcribe([0, 0, 0])
            XCTFail("Expected notLoaded")
        } catch {
            XCTAssertEqual(error as? ParakeetRecognizerError, .notLoaded)
        }
    }

    private static func tone(format: AVAudioFormat, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            data[0][frame] = 0.5 * sin(Float(frame) * 2 * .pi * 440 / Float(format.sampleRate))
        }
        return buffer
    }
}
