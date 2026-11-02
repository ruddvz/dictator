import Foundation

/// Paired bootstrap over clips: is one transcription setup's WER really lower than another's on
/// the same audio, or is the gap within noise? Idea credited to amirrsyed/hushkey (MIT), whose
/// `hushkey eval --compare` reports a paired-bootstrap p-value.
struct PairedComparison: Codable, Equatable {
    var clips: Int
    var baselineWER: Double
    var candidateWER: Double
    /// candidate − baseline; negative means the candidate makes fewer errors.
    var delta: Double
    var low95: Double
    var high95: Double
    /// Share of resamples where the candidate was not better: a one-sided p-value.
    var pValue: Double

    var verdict: String {
        if clips < 5 { return "too few clips to tell" }
        if high95 < 0 { return "candidate better" }
        if low95 > 0 { return "candidate worse" }
        return "no clear difference"
    }
}

enum PairedBootstrap {
    /// `baseline[i]` and `candidate[i]` must score the same clip. Seeded, so reports are reproducible.
    static func compare(baseline: [EditCounts], candidate: [EditCounts],
                        resamples: Int = 2000, seed: UInt64 = 0x48555348) -> PairedComparison? {
        precondition(baseline.count == candidate.count, "paired clips")
        let n = baseline.count
        guard n > 0 else { return nil }
        func wer(_ counts: [EditCounts], _ indices: [Int]) -> Double {
            indices.map { counts[$0] }.reduce(EditCounts(), +).rate
        }
        let all = Array(0..<n)
        let baseRate = wer(baseline, all)
        let candRate = wer(candidate, all)
        var rng = SplitMix64(seed: seed)
        var deltas: [Double] = []
        deltas.reserveCapacity(resamples)
        for _ in 0..<resamples {
            let sample = (0..<n).map { _ in Int(rng.next() % UInt64(n)) }
            deltas.append(wer(candidate, sample) - wer(baseline, sample))
        }
        deltas.sort()
        let notBetter = deltas.filter { $0 >= 0 }.count
        return PairedComparison(clips: n, baselineWER: baseRate, candidateWER: candRate,
                                delta: candRate - baseRate,
                                low95: deltas[Int(Double(resamples) * 0.025)],
                                high95: deltas[min(resamples - 1, Int(Double(resamples) * 0.975))],
                                pValue: Double(notBetter) / Double(resamples))
    }

    /// Pairs clips by split and id across two engine runs (two engines now, or this run against
    /// the previous report), skipping clips that errored in either.
    static func compare(baseline: EngineResult, candidate: EngineResult, split: EvalSplit) -> PairedComparison? {
        let base = Dictionary(baseline.clips.filter { $0.split == split && $0.error == nil }.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        let pairs = candidate.clips.filter { $0.split == split && $0.error == nil }
            .compactMap { clip in base[clip.id].map { ($0.wordErrors, clip.wordErrors) } }
        return compare(baseline: pairs.map(\.0), candidate: pairs.map(\.1))
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
