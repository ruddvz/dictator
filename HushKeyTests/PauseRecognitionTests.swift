import AVFoundation
import XCTest
@testable import HushKey

/// Real on-device recognition over speech with long pauses. Needs Speech permission, so it runs
/// with the eval (`HUSHKEY_EVAL=1`, see Scripts/eval.sh) or `Scripts/check-pauses.sh`.
final class PauseRecognitionTests: XCTestCase {
    @MainActor
    func testEveryPhraseSurvivesLongPauses() async throws {
        guard ProcessInfo.processInfo.environment["HUSHKEY_EVAL"] == "1" else {
            throw XCTSkip("Run Scripts/check-pauses.sh to test real recognition across pauses.")
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "hushkey-pauses-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let script = "Let's meet at three thirty tomorrow. [[slnc 3000]] Please bring the quarterly roadmap. "
            + "[[slnc 4000]] And book a room on the second floor."
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "--file-format=WAVE", "--data-format=LEF32@16000", "-o", url.path, script]
        try say.run()
        say.waitUntilExit()

        let file = try AVAudioFile(forReading: url)
        var buffers: [AVAudioPCMBuffer] = []
        while file.framePosition < file.length {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600))
            try file.read(into: buffer, frameCount: 1600)
            if buffer.frameLength == 0 { break }
            buffers.append(buffer)
        }

        let transcriber = MicTranscriber()
        let started = await transcriber.transcribe(recorded: buffers)
        XCTAssertTrue(started, transcriber.error ?? "did not start")
        let raw = await transcriber.waitForFinalization()
        print("Recognized across pauses: \(raw)")
        let text = raw.lowercased()
        for word in ["meet", "roadmap", "room"] {
            XCTAssertTrue(text.contains(word), "lost \"\(word)\" after a pause: \(text)")
        }
    }
}
