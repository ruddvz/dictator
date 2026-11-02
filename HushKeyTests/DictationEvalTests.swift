import XCTest
@testable import HushKey

/// Deterministic checks run in CI. The audio report runs only from `Scripts/eval.sh` (`HUSHKEY_EVAL=1`).
final class DictationEvalTests: XCTestCase {
    func testWordErrorRateCountsSubstitutionsDeletionsAndInsertions() {
        let counts = EvalScoring.wordErrors(reference: "send the report to Priya",
                                            hypothesis: "Send a report to Priya today.")
        XCTAssertEqual(counts, EditCounts(substitutions: 1, deletions: 0, insertions: 1, referenceTokens: 5))
        XCTAssertEqual(counts.rate, 0.4, accuracy: 0.0001)
        XCTAssertEqual(EvalScoring.wordErrors(reference: "Don’t stop", hypothesis: "don't stop.").errors, 0)
        XCTAssertEqual(EvalScoring.wordErrors(reference: "one two", hypothesis: "").deletions, 2)
        // Recognizer-applied formatting is scored as the spoken command words.
        XCTAssertEqual(EvalScoring.wordErrors(
            reference: "user underscore id equals open parenthesis process dot env close parenthesis new line done",
            hypothesis: "user_ID = (process.env)\nDone.").errors, 0)
    }

    func testFormattedTokensKeepCodeSymbolsAndLineBreaks() {
        XCTAssertEqual(EvalScoring.formattedTokens("let user_id = (value).\nDone, ok"),
                       ["let", "user", "_", "id", "=", "(", "value", ")", "⏎", "done", "ok"])
        XCTAssertEqual(EvalScoring.formattedTokens("process.env.key"), ["process", ".", "env", ".", "key"])
    }

    func testAudioChecksMatchWholeWordsOnly() {
        let check = AudioEvalCheck(contains: ["\n", "ship it"], absent: ["um"])
        XCTAssertEqual(EvalScoring.failedChecks(check, output: "We should\nship it, umbrella."), [])
        XCTAssertEqual(EvalScoring.failedChecks(check, output: "Um ship it"), ["missing \"⏎\"", "contains \"um\""])
    }

    func testEvalSplitsAreDisjoint() throws {
        var processorIDs = Set<String>(), processorInputs = Set<String>()
        var clipIDs = Set<String>(), clipReferences = Set<String>()
        for split in EvalSplit.allCases {
            for item in try EvalFixtures.processorCases(split) {
                XCTAssertTrue(processorIDs.insert(item.id).inserted, "Duplicate processor case ID \(item.id)")
                let key = "\(item.mode)|\(item.snippets ?? "")|\(item.input)|\(item.applyCorrections ?? true)|\(item.cleanupFillers ?? false)"
                XCTAssertTrue(processorInputs.insert(key).inserted, "Processor input repeated across cases: \(item.id)")
                _ = try EvalFixtures.mode(named: item.mode)
            }
            for clip in try EvalFixtures.audioClips(split) {
                XCTAssertTrue(clipIDs.insert(clip.id).inserted, "Duplicate clip ID \(clip.id)")
                XCTAssertTrue(clipReferences.insert(clip.reference.lowercased()).inserted,
                              "Reference repeated across clips: \(clip.id)")
                for mode in (clip.checks ?? [:]).keys { _ = try EvalFixtures.mode(named: mode) }
            }
        }
    }

    /// Fails only on deterministic processor regressions; known gaps are reported in `docs/eval/report.md`.
    func testProcessorHasNoRegressionsInDevOrHoldout() throws {
        for split in EvalSplit.allCases {
            let results = try ProcessorEval.run(split)
            XCTAssertFalse(results.isEmpty, "No processor cases in \(split.rawValue)")
            for result in results where result.isRegression {
                XCTFail("\(split.rawValue)/\(result.id) (\(result.mode)): expected "
                    + "\(EvalScoring.display(result.expected)), got \(EvalScoring.display(result.actual))")
            }
        }
    }

    @MainActor
    func testWriteEvalReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HUSHKEY_EVAL"] == "1" else {
            throw XCTSkip("Run Scripts/eval.sh to transcribe the eval clips and write docs/eval/report.md.")
        }
        let locale = environment["HUSHKEY_EVAL_LOCALE"] ?? "en-US"
        let processor = try EvalSplit.allCases.flatMap { try ProcessorEval.run($0) }

        var engines: [DictationEvalEngine] = [AppleSpeechEvalEngine(localeIdentifier: locale)]
        let installed = WhisperKitEvalEngine.installedVariants()
        engines += installed.map {
            WhisperKitEvalEngine(variant: $0, languageIdentifier: String(locale.prefix(2)))
        }
        var engineResults: [EngineResult] = []
        for engine in engines {
            engineResults.append(try await AudioEval.run(engine, splits: EvalSplit.allCases))
        }
        if installed.isEmpty {
            engineResults.append(EngineResult(
                engine: "whisperkit", skippedReason: "No WhisperKit model is downloaded in HushKey. Download one in "
                    + "Transcribe Files to include it; the harness never downloads models.", clips: []))
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
        let report = EvalReport(
            generatedAt: formatter.string(from: Date()),
            system: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            processor: processor, engines: engineResults)
        // The previous report is the baseline for "did this change help?" before it is overwritten.
        let previous = try? JSONDecoder().decode(
            EvalReport.self, from: Data(contentsOf: EvalPaths.reports.appending(path: "report.json")))
        try EvalReportWriter.write(report, baseline: previous, to: EvalPaths.reports)
        print(EvalReportWriter.markdown(report, baseline: previous))
    }

    func testPairedBootstrapSeparatesRealGainsFromNoise() throws {
        let worse = Array(repeating: EditCounts(substitutions: 2, referenceTokens: 10), count: 12)
        let better = Array(repeating: EditCounts(substitutions: 0, referenceTokens: 10), count: 12)
        let gain = try XCTUnwrap(PairedBootstrap.compare(baseline: worse, candidate: better))
        XCTAssertEqual(gain.delta, -0.2, accuracy: 1e-9)
        XCTAssertLessThan(gain.high95, 0)
        XCTAssertEqual(gain.verdict, "candidate better")
        XCTAssertEqual(gain.pValue, 0)

        let same = PairedBootstrap.compare(baseline: worse, candidate: worse)
        XCTAssertEqual(same?.verdict, "no clear difference")
        XCTAssertEqual(PairedBootstrap.compare(baseline: Array(worse.prefix(3)), candidate: Array(better.prefix(3)))?.verdict,
                       "too few clips to tell")
        XCTAssertEqual(PairedBootstrap.compare(baseline: worse, candidate: better),
                       PairedBootstrap.compare(baseline: worse, candidate: better), "seeded and reproducible")
    }
}
