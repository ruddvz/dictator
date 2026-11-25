import XCTest
import AVFoundation
@testable import Dictator

@MainActor
final class ParakeetFileTranscriberTests: XCTestCase {
    private func makeTone(seconds: Double, sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = buffer.floatChannelData![channel]
            for index in 0..<Int(frames) { data[index] = sinf(Float(index) * 0.05) * 0.5 }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testDecodeResamplesStereo44kToMono16k() async throws {
        let url = try makeTone(seconds: 1, sampleRate: 44_100)
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = try await ParakeetFileTranscriber.decodeSamples(from: url)
        XCTAssertEqual(Double(samples.count), 16_000, accuracy: 400)
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.1)
    }

    func testDecodeRejectsFileWithoutAudio() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).txt")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await ParakeetFileTranscriber.decodeSamples(from: url)
            XCTFail("Expected an error for a non-audio file")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testParakeetSessionRoundTripsThroughJSON() throws {
        let session = FileTranscriptionSession(id: UUID(), sourceName: "a.m4a", engine: .parakeet,
                                               languageIdentifier: "en", text: "hello", cues: [])
        let decoded = try JSONDecoder().decode(FileTranscriptionSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.engine, .parakeet)
        XCTAssertEqual(decoded.text, "hello")
    }

    func testRestoreKeepsTextAndHasNoCues() {
        let transcriber = ParakeetFileTranscriber()
        transcriber.restore(FileTranscriptionSession(id: UUID(), sourceName: "a.m4a", engine: .parakeet,
                                                     languageIdentifier: "en", text: "hello", cues: []))
        XCTAssertEqual(transcriber.text, "hello")
        XCTAssertTrue(transcriber.cues.isEmpty)
    }

    /// Opt-in: runs the real Parakeet model on a real file.
    /// `TEST_RUNNER_DICTATOR_LIVE_FILE=/path/to/audio.aiff TEST_RUNNER_DICTATOR_LIVE_MODEL_ROOT=<ParakeetModels dir> xcodebuild … test`
    func testLiveTranscriptionOfRealFile() async throws {
        guard let path = ProcessInfo.processInfo.environment["DICTATOR_LIVE_FILE"] else {
            throw XCTSkip("Set TEST_RUNNER_DICTATOR_LIVE_FILE to run against the real Parakeet model.")
        }
        let root = ProcessInfo.processInfo.environment["DICTATOR_LIVE_MODEL_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? ParakeetDictationEngine.defaultModelRoot
        let engine = ParakeetDictationEngine(modelRoot: root)
        try XCTSkipUnless(engine.isDownloaded, "Parakeet model is not on this Mac.")
                let transcriber = ParakeetFileTranscriber()
        transcriber.transcribe(file: URL(fileURLWithPath: path), engine: engine,
                               vocabulary: ["Vadodara", "Vercel"])
        let deadline = Date().addingTimeInterval(120)
        while transcriber.isTranscribing, Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        print("LIVE_BOOST_READY:", engine.isVocabularyBoostingReady, "LIVE_RESULT:", transcriber.text, "| error:", transcriber.error ?? "none")
        XCTAssertNil(transcriber.error)
        XCTAssertFalse(transcriber.text.isEmpty)
    }
}
