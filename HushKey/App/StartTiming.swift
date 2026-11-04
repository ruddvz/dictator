import Foundation
import os

/// Measures how long each step between the dictation shortcut and an open microphone takes on
/// the main thread, so a stutter at the start can be traced to its cause. Logged at notice level:
/// `log show --predicate 'subsystem == "com.ruddvz.hushkey" && category == "start"' --last 5m`.
struct StartTiming {
    private static let log = Logger(subsystem: "com.ruddvz.hushkey", category: "start")
    private let begin = ProcessInfo.processInfo.systemUptime
    private var last = ProcessInfo.processInfo.systemUptime
    private(set) var steps: [(String, Double)] = []

    mutating func mark(_ step: String) {
        let now = ProcessInfo.processInfo.systemUptime
        steps.append((step, (now - last) * 1000))
        last = now
    }

    func report(_ outcome: String) {
        let total = (ProcessInfo.processInfo.systemUptime - begin) * 1000
        let detail = steps.map { "\($0.0)=\(String(format: "%.0f", $0.1))" }.joined(separator: " ")
        Self.log.notice("dictation start \(outcome, privacy: .public) total=\(String(format: "%.0f", total), privacy: .public)ms \(detail, privacy: .public)")
    }
}
