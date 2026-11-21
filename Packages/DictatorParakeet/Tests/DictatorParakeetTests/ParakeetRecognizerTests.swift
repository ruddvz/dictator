import AVFoundation
import XCTest
@testable import DictatorParakeet

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
        XCTAssertEqual(ParakeetModel.allCases, [.englishUnified])
        XCTAssertEqual(ParakeetModel.englishUnified.directory(in: root).lastPathComponent,
                       "parakeet-unified-en-0.6b")
        XCTAssertEqual(ParakeetModel.englishUnified.requiredFiles.count, 4)
        XCTAssertFalse(ParakeetModel.englishUnified.isDownloaded(in: root.appending(path: UUID().uuidString)))
    }

    func testTranscribeBeforeLoadingFails() async {
        do {
            _ = try await ParakeetRecognizer().transcribe([0, 0, 0])
            XCTFail("Expected notLoaded")
        } catch {
            XCTAssertEqual(error as? ParakeetRecognizerError, .notLoaded)
        }
    }

    /// Local signal check used to tune the no-speech gate without microphone access.
    func testSilenceAndQuietNoiseDiagnosticsOnDownloadedModel() async throws {
        guard let path = ProcessInfo.processInfo.environment["PARAKEET_MODEL_ROOT"] else {
            throw XCTSkip("Set PARAKEET_MODEL_ROOT to inspect no-speech behavior.")
        }
        let root = URL(fileURLWithPath: path)
        let model = try XCTUnwrap(ParakeetModel.allCases.first { $0.isDownloaded(in: root) })
        let recognizer = ParakeetRecognizer()
        try await recognizer.load(model, from: root)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        for (name, buffer) in [("silence", try Self.tone(format: format, frames: 96_000, amplitude: 0)),
                               ("quiet-tone", try Self.tone(format: format, frames: 96_000, amplitude: 0.003)),
                               ("quiet-noise", try Self.noise(format: format, frames: 96_000, amplitude: 0.01))] {
            let result = try await recognizer.transcribe(ParakeetRecognizer.samples(from: [buffer]))
            print("parakeet-no-speech \(name): confidence=\(result.confidence), text=\(result.text.debugDescription)")
            XCTAssertTrue(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          "Synthetic \(name) should not produce transcript text")
        }
    }

    /// Opt-in timing on a downloaded model: `PARAKEET_MODEL_ROOT=<ParakeetModels folder> swift test`.
    func testLoadAndTranscribeTimingsOnADownloadedModel() async throws {
        guard let path = ProcessInfo.processInfo.environment["PARAKEET_MODEL_ROOT"] else {
            throw XCTSkip("Set PARAKEET_MODEL_ROOT to time a downloaded model.")
        }
        let root = URL(fileURLWithPath: path)
        let model = try XCTUnwrap(ParakeetModel.allCases.first { $0.isDownloaded(in: root) })
        let recognizer = ParakeetRecognizer()
        let clock = ContinuousClock()
        let load = try await clock.measure { try await recognizer.load(model, from: root) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        for seconds in [2, 5, 10, 30] {
            let buffer = try Self.tone(format: format, frames: AVAudioFrameCount(48_000 * seconds))
            let samples = try ParakeetRecognizer.samples(from: [buffer])
            let result = try await recognizer.transcribe(samples)
            print(String(format: "parakeet-timing %@ %ds audio: %.3f s", model.rawValue, seconds, result.processingSeconds))
        }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        print(String(format: "parakeet-timing load+warm-up %.2f s, resident %.0f MB", 
                     Double(load.components.seconds) + Double(load.components.attoseconds) / 1e18,
                     Double(info.resident_size) / 1_048_576))
    }

    private static func tone(format: AVAudioFormat, frames: AVAudioFrameCount,
                             amplitude: Float = 0.5) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            data[0][frame] = amplitude * sin(Float(frame) * 2 * .pi * 440 / Float(format.sampleRate))
        }
        return buffer
    }

    private static func noise(format: AVAudioFormat, frames: AVAudioFrameCount,
                              amplitude: Float) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        var state: UInt32 = 0x12345678
        for frame in 0..<Int(frames) {
            state = 1_664_525 &* state &+ 1_013_904_223
            let unit = Float(state) / Float(UInt32.max)
            data[0][frame] = (unit * 2 - 1) * amplitude
        }
        return buffer
    }
}
