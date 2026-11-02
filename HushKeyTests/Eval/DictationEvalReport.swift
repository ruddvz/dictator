import Foundation

struct EvalReport: Codable {
    var generatedAt: String
    var system: String
    var processor: [ProcessorCaseResult]
    var engines: [EngineResult]
}

enum EvalReportWriter {
    static func write(_ report: EvalReport, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: directory.appending(path: "report.json"))
        try Data(markdown(report).utf8).write(to: directory.appending(path: "report.md"))
    }

    static func markdown(_ report: EvalReport) -> String {
        var lines = [
            "# HushKey dictation eval",
            "",
            "Generated \(report.generatedAt) on \(report.system) by `Scripts/eval.sh`. "
                + "Machine-readable results: [report.json](report.json).",
            "",
            "Tune against **dev**. Treat **holdout** as a fair check: read only its aggregate numbers while changing the processor.",
            "",
            "## Processor checks (deterministic, gated in CI)",
            "",
            "| Split | Passed | Known gaps | Regressions | Known gaps now passing |",
            "|---|---|---|---|---|"
        ]
        for split in EvalSplit.allCases {
            let results = report.processor.filter { $0.split == split }
            lines.append("| \(split.rawValue) | \(fraction(results.filter(\.passed).count, results.count)) | "
                + "\(results.filter { $0.knownGap && !$0.passed }.count) | \(results.filter(\.isRegression).count) | "
                + "\(results.filter(\.isNewlyPassing).count) |")
        }
        lines += ["", "| Category | dev | holdout |", "|---|---|---|"]
        for category in orderedUnique(report.processor.map(\.category)) {
            let cells = EvalSplit.allCases.map { split in
                let results = report.processor.filter { $0.split == split && $0.category == category }
                return fraction(results.filter(\.passed).count, results.count)
            }
            lines.append("| \(category) | \(cells.joined(separator: " | ")) |")
        }
        let devGaps = report.processor.filter { $0.split == .dev && !$0.passed }
        if !devGaps.isEmpty {
            lines += ["", "Dev failures:", ""]
            for result in devGaps {
                lines.append("- `\(result.id)` (\(result.mode))\(result.knownGap ? " known gap" : " **regression**"): "
                    + "expected \(code(result.expected)), got \(code(result.actual))")
            }
        }

        lines += ["", "## Audio pipeline (reported, not gated)", "",
                  "WER compares raw recognition with the spoken reference (case and punctuation ignored; line breaks and code symbols "
                  + "the recognizer inserted itself count as their spoken words). "
                  + "Format TER compares a mode's processed output with the processor applied to the reference, "
                  + "over the clips that target that mode. "
                  + "Checks are per-mode `contains`/`absent` assertions from the fixtures.", ""]
        for engine in report.engines {
            lines.append("### \(engine.engine)")
            lines.append("")
            if let reason = engine.skippedReason {
                lines += ["Skipped: \(reason)", ""]
                continue
            }
            lines += ["| Split | Clips | Sources | WER | Real-time factor | Clip errors |", "|---|---|---|---|---|---|"]
            for split in EvalSplit.allCases {
                let clips = engine.clips.filter { $0.split == split }
                let words = clips.map(\.wordErrors).reduce(EditCounts(), +)
                let audio = clips.map(\.audioSeconds).reduce(0, +)
                let elapsed = clips.map(\.transcribeSeconds).reduce(0, +)
                let sources = orderedUnique(clips.map(\.source))
                    .map { source in "\(clips.filter { $0.source == source }.count) \(source)" }
                    .joined(separator: ", ")
                lines.append("| \(split.rawValue) | \(clips.count) | \(sources) | \(percent(words.rate)) | "
                    + "\(audio > 0 ? String(format: "%.2f×", elapsed / audio) : "—") | "
                    + "\(clips.filter { $0.error != nil }.count) |")
            }
            lines += ["", "| Mode | dev checks | dev format TER | holdout checks | holdout format TER |",
                      "|---|---|---|---|---|"]
            for mode in evalModes.map(\.rawValue) {
                let cells = EvalSplit.allCases.flatMap { split -> [String] in
                    let results = engine.clips.filter { $0.split == split }.flatMap(\.modes)
                        .filter { $0.mode == mode && $0.checksTotal > 0 }
                    let total = results.map(\.checksTotal).reduce(0, +)
                    let failed = results.map(\.failedChecks.count).reduce(0, +)
                    let errors = results.map(\.formattedErrors).reduce(EditCounts(), +)
                    return [total == 0 ? "—" : fraction(total - failed, total), percent(errors.rate)]
                }
                lines.append("| \(mode) | \(cells.joined(separator: " | ")) |")
            }
            lines += ["", "Dev clips:", "", "| Clip | WER | Recognized | Failed checks |", "|---|---|---|---|"]
            for clip in engine.clips where clip.split == .dev {
                let failures = clip.modes.flatMap { mode in mode.failedChecks.map { "\(mode.mode): \($0)" } }
                let recognized = clip.error.map { "error: \($0)" } ?? clip.raw
                lines.append("| `\(clip.id)` | \(percent(clip.wordErrors.rate)) | \(cell(recognized)) | "
                    + "\(failures.isEmpty ? "—" : cell(failures.joined(separator: "; "))) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func fraction(_ passed: Int, _ total: Int) -> String {
        total == 0 ? "—" : "\(passed)/\(total)"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func code(_ text: String) -> String {
        "`" + text.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "`", with: "ˋ") + "`"
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "|", with: "\\|")
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
