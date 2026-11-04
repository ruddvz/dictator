import os
import XCTest
@testable import HushKey

/// The Polished level's local model, scored against `Fixtures/eval/<split>/polish.json`.
///
/// The deterministic checks always run. The model-backed comparison of raw vs polished runs only
/// when a GGUF path is given, so tests never download anything:
///
///     TEST_RUNNER_HUSHKEY_POLISH_MODEL=/path/to/SmolLM2-360M-Instruct-Q4_K_M.gguf xcodebuild … test \
///       -only-testing:HushKeyTests/PolishEvalTests
///
/// It writes `docs/eval/polish-report.md`: per-case results for dev, aggregates only for holdout
/// (see `Fixtures/eval/README.md`).
final class PolishEvalTests: XCTestCase {
    struct PolishCase: Decodable {
        let id: String
        let input: String
        let expected: String
    }

    private struct PolishFile: Decodable { let cases: [PolishCase] }

    static func cases(_ split: EvalSplit) throws -> [PolishCase] {
        let data = try Data(contentsOf: EvalPaths.fixtures(split).appending(path: "polish.json"))
        return try JSONDecoder().decode(PolishFile.self, from: data).cases
    }

    func testPolishFixturesAreDisjointAndExpectedOutputsPassTheSafetyCheck() throws {
        var ids = Set<String>(), inputs = Set<String>()
        for split in EvalSplit.allCases {
            let cases = try Self.cases(split)
            XCTAssertFalse(cases.isEmpty, "No polish cases in \(split.rawValue)")
            for item in cases {
                XCTAssertTrue(ids.insert(item.id).inserted, "Duplicate polish case ID \(item.id)")
                XCTAssertTrue(inputs.insert(item.input.lowercased()).inserted, "Polish input repeated: \(item.id)")
                XCTAssertFalse(DictationSmartCleanup.localExamples.contains { $0.user.lowercased() == item.input.lowercased() },
                               "\(item.id) repeats a few-shot example, so it can't measure anything")
                // An expected answer the delete-only check would reject could never be reached.
                XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(from: item.input, to: item.expected),
                              "\(split.rawValue)/\(item.id): expected output fails isSafeCleanup")
            }
        }
    }

    func testFewShotExamplesPassTheSafetyCheck() {
        for example in DictationSmartCleanup.localExamples {
            XCTAssertTrue(DictationSmartCleanup.isSafeCleanup(from: example.user, to: example.assistant), example.user)
        }
    }

    /// Without Apple Intelligence, Polished becomes selectable exactly when the model is on disk.
    @MainActor
    func testPolishedIsAvailableOnceTheLocalModelIsDownloaded() throws {
        UserDefaults.standard.set(true, forKey: "localCleanupOnly")
        defer { UserDefaults.standard.removeObject(forKey: "localCleanupOnly") }
        let model = LocalCleanupModel.shared
        XCTAssertTrue(model.fileURL.path.contains("hushkey-tests-"), "Tests must not touch the real model folder")
        try? FileManager.default.removeItem(at: model.fileURL)
        XCTAssertFalse(DictationSmartCleanup.isAvailable)
        XCTAssertNil(DictationSmartCleanup.prepare())
        try FileManager.default.createDirectory(at: model.root, withIntermediateDirectories: true)
        try Data().write(to: model.fileURL)
        defer { try? FileManager.default.removeItem(at: model.fileURL) }
        XCTAssertTrue(DictationSmartCleanup.isAvailable)
        XCTAssertEqual(DictationSmartCleanup.engine, .localModel)
    }

    /// Downloads the real pinned model and checks it, like Download in Settings. Network, so opt-in:
    /// `TEST_RUNNER_HUSHKEY_LIVE_DOWNLOAD=1`.
    func testDownloadAndVerifyPinnedModel() async throws {
        guard ProcessInfo.processInfo.environment["HUSHKEY_LIVE_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_HUSHKEY_LIVE_DOWNLOAD=1 to download the cleanup model.")
        }
        let file = LocalCleanupModelFile.default
        let destination = FileManager.default.temporaryDirectory.appending(path: "polish-download-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: destination) }
        let progress = OSAllocatedUnfairLock(initialState: 0.0)
        try await ModelDownloader.download(file.url, to: destination) { fraction in progress.withLock { $0 = fraction } }
        try ModelDownloader.verify(destination, bytes: file.bytes, sha256: file.sha256)
        XCTAssertGreaterThan(progress.withLock { $0 }, 0.99)
        XCTAssertThrowsError(try ModelDownloader.verify(destination, bytes: file.bytes, sha256: String(repeating: "0", count: 64)))
    }

    func testTidyStripsWrappersAndEmptyThinkBlocks() {
        XCTAssertEqual(DictationSmartCleanup.tidy("<think>\n\n</think>\n\nSend it today."), "Send it today.")
        XCTAssertEqual(DictationSmartCleanup.tidy("<dictation>\nSend it today.\n</dictation>"), "Send it today.")
        XCTAssertEqual(DictationSmartCleanup.tidy("  Send it.  "), "Send it.")
    }

    func testDefaultModelIsPinnedToOneFile() {
        XCTAssertTrue(LocalCleanupModelFile.default.url.path().contains("/resolve/7be6f65"))
        XCTAssertEqual(LocalCleanupModelFile.default.url.host(), "huggingface.co")
        XCTAssertEqual(LocalCleanupModelFile.default.sha256.count, 64)
    }

    @MainActor
    func testRawVersusPolishedWithLocalModel() async throws {
        guard let path = ProcessInfo.processInfo.environment["HUSHKEY_POLISH_MODEL"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_HUSHKEY_POLISH_MODEL to a GGUF file to run the polish eval.")
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let file = LocalCleanupModelFile(
            title: name, fileName: name, url: url,
            bytes: (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0,
            sha256: "", assistantPrefix: name.lowercased().hasPrefix("qwen3") ? "<think>\n\n</think>\n\n" : "")
        let model = LocalCleanupModel(file: file, root: url.deletingLastPathComponent())
        defer { model.unloadBeforeExit() }
        let loadStart = ContinuousClock.now
        let loaded = await model.warmUp().value
        XCTAssertTrue(loaded, "\(name) didn't load")
        let loadTime = ContinuousClock.now - loadStart

        var lines = ["# Polish eval: raw vs polished", "",
                     "Model: `\(name)` (\(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))), "
                        + "llama.cpp b11900, greedy, the same instructions as Apple Intelligence. "
                        + "Load: \(Self.format(loadTime)). Generated by `PolishEvalTests` on this Mac.", "",
                     "- **Words match**: same words as `expected`, ignoring case and punctuation.",
                     "- **Exact**: identical to `expected`, punctuation included.",
                     "- **WER**: word error rate against `expected`.",
                     "- **Rejected**: answers `isSafeCleanup` threw away (rewording, dropped words); the rule text is used instead.",
                     ""]
        var summary: [String] = ["| Split | Cases | Raw words match | Polished words match | Raw exact | Polished exact | Raw WER | Polished WER | Rejected | Median | Slowest |",
                                 "|---|---|---|---|---|---|---|---|---|---|---|"]
        var devRows: [String] = ["| Case | Polished output | Kept | Words match | Time |", "|---|---|---|---|---|"]
        for split in EvalSplit.allCases {
            var rawWords = 0, polishedWords = 0, rawExact = 0, polishedExact = 0, rejected = 0
            var rawErrors = EditCounts(), polishedErrors = EditCounts()
            var times: [Duration] = []
            let cases = try Self.cases(split)
            for item in cases {
                let start = ContinuousClock.now
                let answer = await DictationSmartCleanup.localAnswer(item.input, model: model, timeout: 30)
                times.append(ContinuousClock.now - start)
                let cleaned = answer.map(DictationSmartCleanup.tidy)
                let kept = cleaned.map { DictationSmartCleanup.isSafeCleanup(from: item.input, to: $0) } ?? false
                let final = kept ? cleaned! : item.input
                if !kept { rejected += 1 }
                let rawMatch = Self.words(item.input) == Self.words(item.expected)
                let polishedMatch = Self.words(final) == Self.words(item.expected)
                rawWords += rawMatch ? 1 : 0
                polishedWords += polishedMatch ? 1 : 0
                rawExact += item.input == item.expected ? 1 : 0
                polishedExact += final == item.expected ? 1 : 0
                rawErrors.add(EvalScoring.wordErrors(reference: item.expected, hypothesis: item.input))
                polishedErrors.add(EvalScoring.wordErrors(reference: item.expected, hypothesis: final))
                if split == .dev {
                    devRows.append("| \(item.id) | \(Self.cell(cleaned ?? "(no answer)")) | \(kept ? "yes" : "**rejected**") | "
                        + "\(polishedMatch ? "yes" : "no") | \(Self.format(times.last!)) |")
                }
            }
            let sorted = times.sorted()
            summary.append("| \(split.rawValue) | \(cases.count) | \(rawWords) | \(polishedWords) | \(rawExact) | \(polishedExact) | "
                + String(format: "%.1f%% | %.1f%%", rawErrors.rate * 100, polishedErrors.rate * 100)
                + " | \(rejected) | \(Self.format(sorted[sorted.count / 2])) | \(Self.format(sorted.last!)) |")
        }
        lines += ["## Summary", ""] + summary + ["", "## Dev cases", ""] + devRows
        let report = lines.joined(separator: "\n") + "\n"
        let out = ProcessInfo.processInfo.environment["HUSHKEY_POLISH_REPORT"].map { URL(fileURLWithPath: $0) }
            ?? EvalPaths.repoRoot.appending(path: "docs/eval/polish-report.md")
        try report.write(to: out, atomically: true, encoding: .utf8)
        print(report)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "⏎")
    }

    private static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f s", seconds)
    }
}

private extension EditCounts {
    mutating func add(_ other: EditCounts) {
        substitutions += other.substitutions
        deletions += other.deletions
        insertions += other.insertions
        referenceTokens += other.referenceTokens
    }
}
