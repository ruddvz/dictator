import Foundation
@testable import Dictator

/// Fixed evaluation splits. Tune against `dev`; read only aggregate `holdout` scores so it stays a fair check.
enum EvalSplit: String, CaseIterable, Codable {
    case dev
    case holdout
}

enum EvalPaths {
    /// Repository root, resolved from this source file so the harness reads fixtures in place.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Eval
        .deletingLastPathComponent() // DictatorTests
        .deletingLastPathComponent()

    static func fixtures(_ split: EvalSplit) -> URL {
        repoRoot.appending(path: "Fixtures/eval/\(split.rawValue)", directoryHint: .isDirectory)
    }

    /// Consented recordings committed by the user; preferred over synthetic clips with the same ID.
    static func recordedAudio(_ split: EvalSplit) -> URL {
        fixtures(split).appending(path: "audio", directoryHint: .isDirectory)
    }

    /// Clips generated locally by `Scripts/eval.sh` with macOS text-to-speech; never committed.
    static func syntheticAudio(_ split: EvalSplit) -> URL {
        repoRoot.appending(path: ".build/eval-audio/\(split.rawValue)", directoryHint: .isDirectory)
    }

    static let reports = repoRoot.appending(path: "docs/eval", directoryHint: .isDirectory)
}

// MARK: - Fixtures

struct ProcessorEvalCase: Codable {
    var id: String
    var category: String
    var mode: String
    var input: String
    var expected: String
    var snippets: String?
    var applyCorrections: Bool?
    var cleanupFillers: Bool?
    /// Expected output describes intended behavior that is not implemented yet; reported, not gated.
    var knownGap: Bool?
    var note: String?
}

struct AudioEvalCheck: Codable {
    /// Case-insensitive substrings that must appear in the processed output.
    var contains: [String]?
    /// Case-insensitive words or phrases that must not appear as whole words.
    var absent: [String]?
}

struct AudioEvalClip: Codable {
    var id: String
    /// Verbatim spoken words; also the text synthesized for bootstrap clips.
    var reference: String
    var snippets: String?
    var cleanupFillers: Bool?
    var checks: [String: AudioEvalCheck]?
}

enum EvalFixtures {
    private struct ProcessorFile: Codable { var cases: [ProcessorEvalCase] }
    private struct AudioFile: Codable { var clips: [AudioEvalClip] }

    static func processorCases(_ split: EvalSplit) throws -> [ProcessorEvalCase] {
        let data = try Data(contentsOf: EvalPaths.fixtures(split).appending(path: "processor.json"))
        return try JSONDecoder().decode(ProcessorFile.self, from: data).cases
    }

    static func audioClips(_ split: EvalSplit) throws -> [AudioEvalClip] {
        let data = try Data(contentsOf: EvalPaths.fixtures(split).appending(path: "audio.json"))
        return try JSONDecoder().decode(AudioFile.self, from: data).clips
    }

    static func mode(named name: String) throws -> DictationMode {
        guard let mode = DictationMode(rawValue: name) else {
            throw CocoaError(.coderReadCorrupt, userInfo: [NSDebugDescriptionErrorKey: "Unknown dictation mode \(name)"])
        }
        return mode
    }
}

// MARK: - Scoring

struct EditCounts: Codable, Equatable {
    var substitutions = 0
    var deletions = 0
    var insertions = 0
    var referenceTokens = 0

    var errors: Int { substitutions + deletions + insertions }
    var rate: Double {
        referenceTokens == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceTokens)
    }

    static func + (lhs: EditCounts, rhs: EditCounts) -> EditCounts {
        EditCounts(substitutions: lhs.substitutions + rhs.substitutions,
                   deletions: lhs.deletions + rhs.deletions,
                   insertions: lhs.insertions + rhs.insertions,
                   referenceTokens: lhs.referenceTokens + rhs.referenceTokens)
    }
}

enum EvalScoring {
    /// Symbols the recognizer may format itself, mapped back to the spoken commands in the reference.
    private static let spokenSymbols: [(String, String)] = [
        ("\n\n", " new paragraph "), ("\n", " new line "), ("->", " arrow "), ("_", " underscore "),
        ("(", " open parenthesis "), (")", " close parenthesis "), ("[", " open bracket "), ("]", " close bracket "),
        ("{", " open brace "), ("}", " close brace "), ("=", " equals "), (";", " semicolon ")
    ]

    /// Words for recognition scoring: case- and diacritic-folded, punctuation dropped, inner apostrophes kept.
    /// Formatting the recognizer applied on its own (line breaks, code symbols) is scored as the spoken words.
    static func words(_ text: String) -> [String] {
        var folded = fold(text).replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
        for (symbol, spoken) in spokenSymbols { folded = folded.replacingOccurrences(of: symbol, with: spoken) }
        folded = folded
            .replacingOccurrences(of: #"(?<=[\p{L}\p{N}])\.(?=[\p{L}\p{N}])"#, with: " dot ", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
        let kept = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "'" ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Tokens for formatted output: symbols and line breaks count, sentence punctuation before a space does not.
    static func formattedTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        let characters = Array(fold(text))
        func flush() {
            if !word.isEmpty { tokens.append(word) }
            word = ""
        }
        for (index, character) in characters.enumerated() {
            if character.isLetter || character.isNumber || character == "'" {
                word.append(character)
            } else if character == "\n" {
                flush()
                tokens.append("⏎")
            } else if character.isWhitespace {
                flush()
            } else {
                flush()
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let isSentencePunctuation = ".,!?".contains(character) && (next == nil || next!.isWhitespace)
                if !isSentencePunctuation { tokens.append(String(character)) }
            }
        }
        flush()
        return tokens
    }

    /// Levenshtein alignment over tokens, reporting substitutions, deletions, and insertions.
    static func edits(reference: [String], hypothesis: [String]) -> EditCounts {
        let columns = hypothesis.count + 1
        var previous = (0..<columns).map { EditCounts(insertions: $0) }
        for referenceToken in reference {
            var first = previous[0]
            first.deletions += 1
            var current = [first]
            for column in 1..<columns {
                var substitution = previous[column - 1]
                if referenceToken != hypothesis[column - 1] { substitution.substitutions += 1 }
                var deletion = previous[column]
                deletion.deletions += 1
                var insertion = current[column - 1]
                insertion.insertions += 1
                current.append([substitution, deletion, insertion].min { $0.errors < $1.errors }!)
            }
            previous = current
        }
        var result = previous[columns - 1]
        result.referenceTokens = reference.count
        return result
    }

    static func wordErrors(reference: String, hypothesis: String) -> EditCounts {
        edits(reference: words(reference), hypothesis: words(hypothesis))
    }

    static func formattedErrors(expected: String, actual: String) -> EditCounts {
        edits(reference: formattedTokens(expected), hypothesis: formattedTokens(actual))
    }

    /// Returns the failed check descriptions for one processed output.
    static func failedChecks(_ check: AudioEvalCheck, output: String) -> [String] {
        var failures: [String] = []
        for needle in check.contains ?? [] where output.range(of: needle, options: [.caseInsensitive]) == nil {
            failures.append("missing \(display(needle))")
        }
        for phrase in check.absent ?? [] {
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}_])"
            if output.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                failures.append("contains \(display(phrase))")
            }
        }
        return failures
    }

    static func display(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\n", with: "⏎") + "\""
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
    }
}

// MARK: - Deterministic processor checks

struct ProcessorCaseResult: Codable {
    var id: String
    var split: EvalSplit
    var category: String
    var mode: String
    var knownGap: Bool
    var passed: Bool
    var expected: String
    var actual: String
    var note: String?

    /// A failure outside the known-gap list; these fail `xcodebuild test`.
    var isRegression: Bool { !passed && !knownGap }
    /// A known gap that now produces the intended output; remove its `knownGap` flag.
    var isNewlyPassing: Bool { passed && knownGap }
}

enum ProcessorEval {
    static func run(_ split: EvalSplit) throws -> [ProcessorCaseResult] {
        try EvalFixtures.processorCases(split).map { item in
            let actual = DictationTranscriptProcessor.process(
                item.input,
                mode: try EvalFixtures.mode(named: item.mode),
                snippets: item.snippets ?? "",
                applyCorrections: item.applyCorrections ?? true,
                cleanupFillers: item.cleanupFillers ?? false)
            return ProcessorCaseResult(id: item.id, split: split, category: item.category, mode: item.mode,
                                       knownGap: item.knownGap ?? false, passed: actual == item.expected,
                                       expected: item.expected, actual: actual, note: item.note)
        }
    }
}
