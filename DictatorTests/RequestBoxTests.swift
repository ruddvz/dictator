import AVFoundation
import Speech
import XCTest
@testable import Dictator

final class RequestBoxTests: XCTestCase {
    private func buffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
        return buffer
    }

    func testAudioBeforeRecognitionIsKeptAndHandedOver() {
        let box = RequestBox()
        box.bufferUntilRequest()
        for _ in 0..<3 { box.append(buffer()) }
        XCTAssertEqual(box.pendingCount, 3)
        box.set(SFSpeechAudioBufferRecognitionRequest())
        XCTAssertEqual(box.pendingCount, 0, "Handed to the request")
        box.append(buffer())
        XCTAssertEqual(box.pendingCount, 0, "Goes straight to the request once it exists")
    }

    func testNothingIsKeptUnlessAsked() {
        let box = RequestBox()
        box.append(buffer())
        XCTAssertEqual(box.pendingCount, 0)
    }

    func testStoppingDropsWhatWasBuffered() {
        let box = RequestBox()
        box.bufferUntilRequest()
        box.append(buffer())
        box.set(nil)
        box.append(buffer())
        XCTAssertEqual(box.pendingCount, 0)
    }

    func testBufferingIsCapped() {
        let box = RequestBox()
        box.bufferUntilRequest()
        let one = buffer()
        for _ in 0..<(RequestBox.maximumPendingBuffers + 10) { box.append(one) }
        XCTAssertEqual(box.pendingCount, RequestBox.maximumPendingBuffers)
    }
}
