import Foundation

enum DictationInsertionGate {
    static func blockedReason(audioIsRunning: Bool, recognitionIsRunning: Bool,
                              isFinalizing: Bool, meetingCaptureIsActive: Bool = false) -> String? {
        if meetingCaptureIsActive {
            return "Stop meeting capture before inserting text."
        }
        if isFinalizing {
            return "Wait for the local transcript to finish before inserting it."
        }
        if audioIsRunning || recognitionIsRunning {
            return "Stop recording and wait for the final transcript before inserting it."
        }
        return nil
    }
}
