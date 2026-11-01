import Foundation

enum DictationInsertionGate {
    static func blockedReason(audioIsRunning: Bool, recognitionIsRunning: Bool, isFinalizing: Bool) -> String? {
        if isFinalizing {
            return "Wait for the local transcript to finish before inserting it."
        }
        if audioIsRunning || recognitionIsRunning {
            return "Stop recording and wait for the final transcript before inserting it."
        }
        return nil
    }
}
