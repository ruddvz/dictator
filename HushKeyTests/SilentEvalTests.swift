import XCTest
@testable import HushKey

/// Offline Silent Use eval: re-scores the silent takes in a saved dataset under several pipeline variants,
/// so a decoding change can be judged on real motion instead of synthetic bursts. Writes only aggregate
/// numbers to docs/eval/silent-report.md; the motion data never leaves the dataset file.
final class SilentEvalTests: XCTestCase {
    private struct Variant {
        var name: String
        var featureSet: FeatureSet = .all
        var smoothing = MotionFeatures.defaultSmoothing
        var headCutoff: Double? = nil
        var cleanTakesOnly = false
    }

    func testWriteSilentEvalReport() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["HUSHKEY_SILENT_DATASET"] else {
            throw XCTSkip("Run Scripts/silent-eval.sh to score your saved silent takes and write docs/eval/silent-report.md.")
        }
        let dataset = try XCTUnwrap(TemplateStore.load(from: URL(fileURLWithPath: path)), "Could not read \(path)")
        let silent = dataset.templates.filter { ($0.condition ?? .silent) == .silent }
        let clean = silent.filter { MotionFeatures.takeIssue($0.samples) == nil }
        let permutations = Int(environment["HUSHKEY_SILENT_PERMUTATIONS"] ?? "") ?? 500

        let variants = [
            Variant(name: "Before: no smoothing, all takes", smoothing: 1),
            Variant(name: "Before, clean takes only", smoothing: 1, cleanTakesOnly: true),
            Variant(name: "Now: 3-sample smoothing, all takes"),
            Variant(name: "Now, clean takes only", cleanTakesOnly: true),
            Variant(name: "Now, clean, rotation only", featureSet: .rotation, cleanTakesOnly: true),
            Variant(name: "Now, clean, acceleration only", featureSet: .acceleration, cleanTakesOnly: true),
            Variant(name: "Now, clean, attitude only", featureSet: .attitude, cleanTakesOnly: true),
            Variant(name: "Now, clean, rotation + acceleration", featureSet: [.rotation, .acceleration], cleanTakesOnly: true),
            Variant(name: "Drift removed (0.3 Hz), clean, all features", headCutoff: 0.3, cleanTakesOnly: true),
            Variant(name: "Drift removed (0.5 Hz), clean, all features", headCutoff: 0.5, cleanTakesOnly: true),
            Variant(name: "Head band removed (1.5 Hz), clean, rotation + acceleration",
                    featureSet: [.rotation, .acceleration], headCutoff: 1.5, cleanTakesOnly: true),
        ]

        var lines = [
            "# Silent Use offline eval",
            "",
            "Generated \(ISO8601DateFormatter().string(from: Date())) by `Scripts/silent-eval.sh`.",
            "",
            "Silent takes: \(silent.count) (\(clean.count) clean; the rest are too short, too long, or include a head turn). "
                + "Sessions: \(Set(silent.compactMap(\.sessionID)).count). Words: "
                + Dictionary(grouping: silent, by: \.label).map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ") + ".",
            "",
            "Leave-one-out accuracy, majority-class chance, and a \(permutations)-label-permutation p-value. "
                + "Held-out session accuracy appears once two sessions each hold every word.",
            "",
            "| Variant | Takes | Accuracy | Chance | p | Held-out session |",
            "|---|---:|---:|---:|---:|---:|",
        ]
        for variant in variants {
            let templates = variant.cleanTakesOnly ? clean : silent
            guard let result = Evaluation.run(templates: templates, featureSet: variant.featureSet,
                                              permutations: permutations, smoothing: variant.smoothing,
                                              headCutoff: variant.headCutoff) else {
                lines.append("| \(variant.name) | \(templates.count) | – | – | – | – |")
                continue
            }
            let holdout = result.sessionHoldoutAccuracy.map {
                String(format: "%.0f %% (chance %.0f %%)", $0 * 100, (result.sessionHoldoutChance ?? 0) * 100)
            } ?? "–"
            lines.append(String(format: "| %@ | %d | %.0f %% | %.0f %% | %.3f | %@ |", variant.name, result.templateCount,
                                result.accuracy * 100, result.chance * 100, result.pValue, holdout))
        }
        let markdown = lines.joined(separator: "\n") + "\n"
        let output = EvalPaths.repoRoot.appending(path: "docs/eval/silent-report.md")
        try markdown.write(to: output, atomically: true, encoding: .utf8)
        print(markdown)
    }
}
