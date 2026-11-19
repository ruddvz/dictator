import Foundation

/// How long saved transcripts stay on this Mac. Everything is local; pruning only deletes.
enum DictationHistoryRetention: String, CaseIterable, Identifiable {
    case forever
    case thirtyDays
    case sevenDays
    case oneDay

    static let preferenceKey = "dictationHistoryRetention"
    static let `default` = DictationHistoryRetention.forever
    var id: String { rawValue }

    var label: String {
        switch self {
        case .forever: "Keep"
        case .thirtyDays: "30 days"
        case .sevenDays: "7 days"
        case .oneDay: "24 hours"
        }
    }

    var maximumAge: TimeInterval? {
        switch self {
        case .forever: nil
        case .thirtyDays: 30 * 86_400
        case .sevenDays: 7 * 86_400
        case .oneDay: 86_400
        }
    }

    /// The entries that are still young enough to keep, in their original order.
    /// An entry dated in the future (a clock change) is kept rather than guessed at.
    func pruning(_ entries: [DictationHistoryEntry], now: Date = Date()) -> [DictationHistoryEntry] {
        guard let maximumAge else { return entries }
        let cutoff = now.addingTimeInterval(-maximumAge)
        return entries.filter { $0.createdAt >= cutoff }
    }
}
