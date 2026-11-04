import Foundation

struct Template: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var label: String
    var samples: [MotionSample]
    var createdAt = Date()
    var condition: SessionRecorder.Condition? = nil
    var sessionID: UUID? = nil

    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.t - first.t
    }
}

struct RankedLabel: Identifiable, Hashable, Sendable {
    var label: String
    var distance: Double
    var id: String { label }
}

struct Prediction: Hashable, Sendable {
    var ranked: [RankedLabel]
    /// 0…1 margin between the best and second-best class.
    var confidence: Double
    var accepted: Bool

    var best: RankedLabel? { ranked.first }
}

/// Small-vocabulary recognizer: nearest-neighbour DTW against user-recorded templates.
/// Deliberately simple — the question this prototype answers is whether the signal is
/// there at all, not how far a big model can push it.
struct TemplateClassifier: Sendable {
    /// Takes of this word (still, mouth closed) teach the classifier what to ignore. A match is never typed.
    static let restLabel = "nothing"

    let featureSet: FeatureSet
    let smoothing: Int
    let headCutoff: Double?
    private let entries: [(label: String, frames: [[Double]])]
    private let scales: [Double]

    var labels: [String] { Array(Set(entries.map(\.label))).sorted() }

    init?(templates: [Template], featureSet: FeatureSet, smoothing: Int = MotionFeatures.defaultSmoothing,
          headCutoff: Double? = nil) {
        guard !featureSet.isEmpty else { return nil }
        let raw = templates.map {
            MotionFeatures.frames(MotionFeatures.trim($0.samples), set: featureSet, smoothing: smoothing,
                                  headCutoff: headCutoff)
        }
        guard Set(templates.map(\.label)).count >= 2 else { return nil }
        let scales = MotionFeatures.channelScales(raw)
        self.featureSet = featureSet
        self.smoothing = smoothing
        self.headCutoff = headCutoff
        self.scales = scales
        self.entries = zip(templates, raw).map { ($0.label, MotionFeatures.scaled($1, by: scales)) }
    }

    func rank(_ samples: [MotionSample]) -> [RankedLabel] {
        let query = MotionFeatures.scaled(
            MotionFeatures.frames(MotionFeatures.trim(samples), set: featureSet, smoothing: smoothing,
                                  headCutoff: headCutoff), by: scales)
        var best: [String: Double] = [:]
        for entry in entries {
            let d = DTW.distance(query, entry.frames)
            best[entry.label] = min(best[entry.label] ?? .infinity, d)
        }
        return best.map { RankedLabel(label: $0.key, distance: $0.value) }.sorted { $0.distance < $1.distance }
    }

    func predict(_ samples: [MotionSample], maxDistance: Double, minConfidence: Double) -> Prediction {
        let ranked = rank(samples)
        let confidence = Self.margin(ranked.map(\.distance))
        let accepted = (ranked.first?.distance ?? .infinity) <= maxDistance && confidence >= minConfidence
            && ranked.first?.label != Self.restLabel
        return Prediction(ranked: ranked, confidence: confidence, accepted: accepted)
    }

    static func margin(_ sortedDistances: [Double]) -> Double {
        guard sortedDistances.count >= 2, sortedDistances[1] > 0 else { return 0 }
        return max(0, 1 - sortedDistances[0] / sortedDistances[1])
    }
}

/// Leave-one-out accuracy plus a label-permutation test: the honest answer to
/// "is the motion stream statistically distinguishable between words?"
struct Evaluation: Sendable {
    var labels: [String]
    /// confusion[actual][predicted]
    var confusion: [[Int]]
    var accuracy: Double
    /// Accuracy of always guessing the most common label.
    var chance: Double
    var permutationMean: Double
    var permutationP95: Double
    var pValue: Double
    var permutations: Int
    var templateCount: Int
    var sessionHoldoutAccuracy: Double?
    var sessionHoldoutChance: Double?
    var sessionHoldoutSessions: Int
    /// True only when every scored fold contains every label with the documented minimum takes.
    var sessionHoldoutComplete: Bool

    static func run(templates: [Template], featureSet: FeatureSet, permutations: Int = 500,
                    smoothing: Int = MotionFeatures.defaultSmoothing,
                    headCutoff: Double? = nil) -> Evaluation? {
        let labels = Array(Set(templates.map(\.label))).sorted()
        let counts = Dictionary(grouping: templates, by: \.label).mapValues(\.count)
        guard labels.count >= 2, counts.values.allSatisfy({ $0 >= 2 }), !featureSet.isEmpty else { return nil }

        let raw = templates.map {
            MotionFeatures.frames(MotionFeatures.trim($0.samples), set: featureSet, smoothing: smoothing,
                                  headCutoff: headCutoff)
        }
        let scales = MotionFeatures.channelScales(raw)
        let seqs = raw.map { MotionFeatures.scaled($0, by: scales) }
        let n = seqs.count

        // Pairwise distances once; every labelling (true or permuted) reuses them.
        var distance = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<max(i + 1, n) {
                let d = DTW.distance(seqs[i], seqs[j])
                distance[i][j] = d
                distance[j][i] = d
            }
        }

        let index = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let truth = templates.map { index[$0.label]! }

        func leaveOneOut(_ assignment: [Int]) -> [Int] {
            (0..<n).map { i in
                var best = [Double](repeating: .infinity, count: labels.count)
                for j in 0..<n where j != i {
                    best[assignment[j]] = min(best[assignment[j]], distance[i][j])
                }
                return best.indices.min { best[$0] < best[$1] }!
            }
        }

        func accuracy(_ predicted: [Int], _ actual: [Int]) -> Double {
            Double(zip(predicted, actual).filter { $0 == $1 }.count) / Double(n)
        }

        let predicted = leaveOneOut(truth)
        var confusion = [[Int]](repeating: [Int](repeating: 0, count: labels.count), count: labels.count)
        for (p, a) in zip(predicted, truth) { confusion[a][p] += 1 }
        let observed = accuracy(predicted, truth)
        let sessionHoldout = leaveOneSessionOut(templates: templates, rawSequences: raw, labels: labels)

        var generator = SystemRandomNumberGenerator()
        var nullAccuracies: [Double] = []
        nullAccuracies.reserveCapacity(permutations)
        for _ in 0..<permutations {
            let shuffled = truth.shuffled(using: &generator)
            nullAccuracies.append(accuracy(leaveOneOut(shuffled), shuffled))
        }
        nullAccuracies.sort()
        let atLeast = nullAccuracies.filter { $0 >= observed }.count

        return Evaluation(
            labels: labels,
            confusion: confusion,
            accuracy: observed,
            chance: Double(counts.values.max() ?? 0) / Double(max(n, 1)),
            permutationMean: nullAccuracies.reduce(0, +) / Double(max(permutations, 1)),
            permutationP95: nullAccuracies.isEmpty ? 0 : nullAccuracies[Int(Double(nullAccuracies.count - 1) * 0.95)],
            pValue: Double(atLeast + 1) / Double(permutations + 1),
            permutations: permutations,
            templateCount: n,
            sessionHoldoutAccuracy: sessionHoldout?.accuracy,
            sessionHoldoutChance: sessionHoldout?.chance,
            sessionHoldoutSessions: sessionHoldout?.sessions ?? 0,
            sessionHoldoutComplete: sessionHoldout?.complete ?? false)
    }

    /// The UI asks for three takes of every word in each session. A holdout score is
    /// meaningful only when every session can train and test the same complete label set.
    private static let minimumSessionTakesPerLabel = 3

    private static func leaveOneSessionOut(
        templates: [Template], rawSequences: [[[Double]]], labels: [String]
    ) -> (accuracy: Double, chance: Double, sessions: Int, complete: Bool)? {
        guard templates.allSatisfy({ $0.sessionID != nil }) else { return nil }
        let sessions = Array(Set(templates.compactMap(\.sessionID)))
        guard sessions.count >= 2 else { return nil }

        var correct = 0
        var baselineCorrect = 0.0
        var tested = 0
        var completedSessions = 0
        let expectedLabels = Set(labels)
        for heldOut in sessions {
            let test = templates.indices.filter { templates[$0].sessionID == heldOut }
            let train = templates.indices.filter { templates[$0].sessionID != heldOut }
            let trainingCounts = Dictionary(grouping: train, by: { templates[$0].label }).mapValues(\.count)
            let testCounts = Dictionary(grouping: test, by: { templates[$0].label }).mapValues(\.count)
            guard expectedLabels.allSatisfy({ label in
                (trainingCounts[label] ?? 0) >= minimumSessionTakesPerLabel &&
                (testCounts[label] ?? 0) >= minimumSessionTakesPerLabel
            }) else { return nil }
            let scales = MotionFeatures.channelScales(train.map { rawSequences[$0] })
            let trainingSequences = Dictionary(uniqueKeysWithValues: train.map { ($0, MotionFeatures.scaled(rawSequences[$0], by: scales)) })

            for i in test {
                var nearest: [String: Double] = [:]
                let query = MotionFeatures.scaled(rawSequences[i], by: scales)
                for j in train {
                    let distance = DTW.distance(query, trainingSequences[j] ?? [])
                    nearest[templates[j].label] = min(nearest[templates[j].label] ?? .infinity, distance)
                }
                if nearest.min(by: { $0.value < $1.value })?.key == templates[i].label { correct += 1 }
            }
            tested += test.count
            baselineCorrect += Double(test.count) * Double(trainingCounts.values.max() ?? 0) / Double(train.count)
            completedSessions += 1
        }
        guard completedSessions >= 2, tested > 0 else { return nil }
        return (Double(correct) / Double(tested), baselineCorrect / Double(tested), completedSessions, true)
    }
}
