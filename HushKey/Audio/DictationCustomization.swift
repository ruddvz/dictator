import Foundation
import Speech

struct DictationLanguage: Identifiable, Hashable {
    let identifier: String
    let name: String
    var id: String { identifier }

    static let onDevice: [DictationLanguage] = SFSpeechRecognizer.supportedLocales().compactMap { locale in
        guard SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true else { return nil }
        let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return DictationLanguage(identifier: locale.identifier, name: name)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

enum DictationMode: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic"
    case natural = "Natural"
    case message = "Message"
    case email = "Email"
    case code = "Code"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .automatic: "sparkles"
        case .natural: "text.alignleft"
        case .message: "bubble.left"
        case .email: "envelope"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    static func resolved(_ requested: DictationMode, bundleIdentifier: String?) -> DictationMode {
        guard requested == .automatic else { return requested }
        let bundle = (bundleIdentifier ?? "").lowercased()
        if bundle == "com.apple.mail" || bundle.contains("outlook") { return .email }
        if bundle == "com.apple.mobilesms" || bundle.contains("slack") ||
            bundle.contains("discord") || bundle.contains("teams") { return .message }
        if bundle == "com.apple.dt.xcode" || bundle.contains("vscode") ||
            bundle.contains("cursor") || bundle.contains("antigravity") ||
            bundle.contains("jetbrains") || bundle == "com.apple.terminal" ||
            bundle == "com.googlecode.iterm2" || bundle == "com.mitchellh.ghostty" { return .code }
        return .natural
    }
}

struct DictationAppProfile: Codable, Identifiable, Equatable {
    var appName: String
    var bundleIdentifier: String
    var mode: DictationMode
    var vocabulary: String

    var id: String { Self.normalizedBundleIdentifier(bundleIdentifier) }

    static func normalizedBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard value.utf8.count <= 255,
              let expression = try? NSRegularExpression(pattern: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range)?.range == range
    }

    static func profile(for bundleIdentifier: String?, in profiles: [DictationAppProfile]) -> DictationAppProfile? {
        guard let bundleIdentifier else { return nil }
        let key = normalizedBundleIdentifier(bundleIdentifier)
        guard !key.isEmpty else { return nil }
        return profiles.first { normalizedBundleIdentifier($0.bundleIdentifier) == key }
    }

    static func upserting(_ profile: DictationAppProfile, into profiles: [DictationAppProfile]) -> [DictationAppProfile] {
        let key = normalizedBundleIdentifier(profile.bundleIdentifier)
        guard !key.isEmpty else { return profiles }
        var result = profiles.filter { normalizedBundleIdentifier($0.bundleIdentifier) != key }
        result.append(profile)
        return result.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    static func resolvedMode(requested: DictationMode, bundleIdentifier: String?, profiles: [DictationAppProfile]) -> DictationMode {
        guard requested == .automatic else { return requested }
        if let profile = profile(for: bundleIdentifier, in: profiles), profile.mode != .automatic {
            return profile.mode
        }
        return DictationMode.resolved(requested, bundleIdentifier: bundleIdentifier)
    }

    static func vocabulary(for bundleIdentifier: String?, in profiles: [DictationAppProfile]) -> [String] {
        guard let profile = profile(for: bundleIdentifier, in: profiles) else { return [] }
        return DictationVocabulary.terms(from: profile.vocabulary)
    }
}

enum DictationContextHintExtractor {
    private static let stopWords: Set<String> = [
        "about", "after", "again", "also", "and", "are", "been", "before", "being", "but",
        "can", "could", "did", "does", "for", "from", "get", "had", "has", "have", "her",
        "here", "him", "his", "how", "into", "its", "just", "like", "make", "more", "most",
        "not", "our", "out", "over", "please", "project", "same", "should", "some", "such", "than", "that",
        "the", "their", "them", "then", "there", "these", "they", "this", "those", "through",
        "under", "until", "very", "want", "was", "were", "what", "when", "where", "which",
        "while", "with", "would", "you", "your"
    ]

    static func extract(from text: String, limit: Int = 24) -> [String] {
        guard limit > 0,
              let expression = try? NSRegularExpression(pattern: #"[\p{L}_$][\p{L}\p{N}_$.-]{2,}"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var distinctiveHints: [String] = []
        var otherHints: [String] = []
        for match in expression.matches(in: text, range: range).reversed() {
            guard let wordRange = Range(match.range, in: text) else { continue }
            let word = String(text[wordRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".-$"))
            guard word.count >= 3,
                  !stopWords.contains(word.lowercased()),
                  seen.insert(word.lowercased()).inserted else { continue }
            let distinctive = word.contains(where: \.isNumber) || word.contains("_") || word.contains(".") ||
                word.rangeOfCharacter(from: .uppercaseLetters) != nil
            guard distinctive || word.count >= 5 else { continue }
            if distinctive { distinctiveHints.append(word) }
            else { otherHints.append(word) }
        }
        return Array((distinctiveHints + otherHints).prefix(limit))
    }
}

enum DictationBacktrack {
    private static let markerExpression = try! NSRegularExpression(
        pattern: #"(?:,\s*|;\s*)(?:scratch\s+that|actually|i\s+mean|no)\s*,?\s+"#,
        options: [.caseInsensitive])
    private static let anchorExpression = try! NSRegularExpression(
        pattern: #"(?i)\b(called|named|equals)\s+([\p{L}\p{N}_'’.-]+(?:\s+[\p{L}\p{N}_'’.-]+){0,3})$"#)
    private static let wordExpression = try! NSRegularExpression(pattern: #"[\p{L}\p{N}_'’.-]+"#)
    private static let safeTailBoundaries: Set<String> = [
        "a", "an", "for", "from", "meet", "my", "on", "prefer", "select", "send", "take", "the", "to", "use", "with", "your"
    ]

    /// Applies only explicit mid-sentence correction cues; raw recognition remains available to restore.
    static func apply(to raw: String) -> String {
        var result = raw
        for _ in 0..<8 {
            let fullRange = NSRange(result.startIndex..., in: result)
            let nsResult = result as NSString
            guard let match = markerExpression.matches(in: result, range: fullRange).last else { break }
            let prefixRaw = nsResult.substring(to: match.range.location)
            let suffixRaw = nsResult.substring(from: NSMaxRange(match.range))
            let prefix = prefixRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"[,;:]$"#, with: "", options: .regularExpression)
            let suffix = suffixRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !suffix.isEmpty,
                  wordExpression.numberOfMatches(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)) <= 8 else { break }

            let prefixNSString = prefix as NSString
            let anchorRange = anchorExpression.firstMatch(in: prefix,
                                                          range: NSRange(location: 0, length: prefixNSString.length))
            var correctedPrefix = prefix
            if let anchorRange, anchorRange.range(at: 2).location != NSNotFound,
               let tailRange = Range(anchorRange.range(at: 2), in: prefix) {
                correctedPrefix.replaceSubrange(tailRange, with: suffix)
            } else {
                let suffixWords = wordExpression.numberOfMatches(in: suffix,
                    range: NSRange(suffix.startIndex..., in: suffix))
                let prefixWords = wordExpression.matches(in: prefix,
                    range: NSRange(prefix.startIndex..., in: prefix))
                guard suffixWords > 0, suffixWords <= 4,
                      prefixWords.count > suffixWords + 1,
                      let removalStart = Range(prefixWords[prefixWords.count - suffixWords].range, in: prefix)?.lowerBound else {
                    break
                }
                let boundaryRange = prefixWords[prefixWords.count - suffixWords - 1].range
                guard let boundary = Range(boundaryRange, in: prefix),
                      safeTailBoundaries.contains(String(prefix[boundary]).lowercased()) else { break }
                correctedPrefix = String(prefix[..<removalStart]).trimmingCharacters(in: .whitespacesAndNewlines)
                if correctedPrefix.isEmpty { break }
                correctedPrefix += " " + suffix
            }

            let leading = String(prefixRaw.prefix(while: { $0.isWhitespace || $0.isNewline }))
            result = leading + correctedPrefix
        }
        return result
    }
}

enum DictationCodeFormatter {
    private static let replacements: [(String, String)] = [
        (#"new\s+line"#, "\n"),
        (#"open\s+parenthesis"#, "("), (#"close\s+parenthesis"#, ")"),
        (#"open\s+bracket"#, "["), (#"close\s+bracket"#, "]"),
        (#"open\s+brace"#, "{"), (#"close\s+brace"#, "}"),
        (#"double\s+quote"#, "\""), (#"single\s+quote"#, "'"),
        (#"underscore"#, "_"), (#"backtick"#, "`"),
        (#"equals"#, "="), (#"arrow"#, "->"),
        (#"semicolon"#, ";"), (#"colon"#, ":"),
        (#"comma"#, ","), (#"dot"#, "."), (#"slash"#, "/"),
        (#"hyphen|dash"#, "-")
    ]

    static func format(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in replacements {
            guard let expression = try? NSRegularExpression(pattern: #"\b(?:"# + pattern + #")\b"#,
                                                           options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        result = result.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([(\[{])\s+"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([)\]}])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*_\s*"#, with: "_", options: .regularExpression)
        return result.replacingOccurrences(of: #"[ \t]+([,.;:])"#, with: "$1", options: .regularExpression)
    }
}

enum DictationModeFormatter {
    static func format(_ text: String, mode: DictationMode) -> String {
        guard mode == .message || mode == .email else { return text }
        var result = text
        let paragraphBreak = mode == .email ? "\n\n" : "\n"
        let replacements = [(#"new\s+paragraph"#, paragraphBreak), (#"new\s+line"#, "\n")]
        for (pattern, replacement) in replacements {
            guard let expression = try? NSRegularExpression(pattern: #"\b(?:"# + pattern + #")\b"#,
                                                           options: [.caseInsensitive]) else { continue }
            result = expression.stringByReplacingMatches(in: result,
                                                         range: NSRange(result.startIndex..., in: result),
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        return result.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
    }
}

enum DictationTranscriptProcessor {
    static func process(_ raw: String, mode: DictationMode, snippets: String,
                        applyCorrections: Bool = true, cleanupFillers: Bool = false) -> String {
        var result = applyCorrections ? DictationBacktrack.apply(to: raw) : raw
        if cleanupFillers { result = DictationLocalCleanup.removeFillers(from: result) }
        if mode == .code { result = DictationCodeFormatter.format(result) }
        else { result = DictationModeFormatter.format(result, mode: mode) }
        return DictationSnippetExpander.expand(result, definitions: snippets)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DictationLocalCleanup {
    private static let fillerExpression = try! NSRegularExpression(
        pattern: #"(?i)(?:,\s*|\s+)?(?<![\p{L}\p{N}_])(?:um+|uh+|erm+)(?![\p{L}\p{N}_])(?:\s*,)?"#)

    /// Conservative, optional cleanup: removes only standalone filler words.
    static func removeFillers(from text: String) -> String {
        var result = fillerExpression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        result = result.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^[\s,;:!?]+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DictationSnippetExpander {
    static func validation(for definitions: String) -> (validCount: Int, invalidLines: [Int]) {
        var validCount = 0
        var invalidLines: [Int] = []
        var seenCues = Set<String>()
        for (offset, rawLine) in definitions.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.components(separatedBy: "=>")
            let cue = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let replacement = parts.dropFirst().joined(separator: "=>").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let hasValidPattern = !cue.isEmpty && (try? NSRegularExpression(pattern: boundaryPattern(for: cue))) != nil
            if parts.count >= 2, hasValidPattern, !replacement.isEmpty, seenCues.insert(key).inserted {
                validCount += 1
            } else {
                invalidLines.append(offset + 1)
            }
        }
        return (validCount, invalidLines)
    }

    /// Lines use `spoken cue => expanded text`; only complete word or phrase matches expand.
    static func expand(_ text: String, definitions: String) -> String {
        var result = text
        let snippets = definitions
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                let parts = line.components(separatedBy: "=>")
                guard parts.count >= 2 else { return nil }
                let cue = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = parts.dropFirst().joined(separator: "=>").trimmingCharacters(in: .whitespacesAndNewlines)
                return cue.isEmpty || replacement.isEmpty ? nil : (cue, replacement)
            }
            .reduce(into: [(String, String)]()) { unique, snippet in
                let alreadyPresent = unique.contains {
                    $0.0.compare(snippet.0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                if !alreadyPresent { unique.append(snippet) }
            }
            .sorted { $0.0.count > $1.0.count }

        for (cue, replacement) in snippets {
            guard let expression = try? NSRegularExpression(
                pattern: boundaryPattern(for: cue) + "([,.;:!?])?",
                options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            for match in expression.matches(in: result, range: range).reversed() {
                guard let whole = Range(match.range, in: result) else { continue }
                let hasFollowingPunctuation = match.range(at: 1).location != NSNotFound && match.range(at: 1).length > 0
                let punctuation = hasFollowingPunctuation
                    ? String(result[Range(match.range(at: 1), in: result)!])
                    : ""
                var expanded = replacement
                if hasFollowingPunctuation, let last = expanded.last, ".!?".contains(last) {
                    expanded.removeLast()
                }
                result.replaceSubrange(whole, with: expanded + punctuation)
            }
        }
        return result
    }

    private static func boundaryPattern(for cue: String) -> String {
        "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: cue) + "(?![\\p{L}\\p{N}_])"
    }
}

enum DictationVocabulary {
    static func terms(from source: String) -> [String] {
        let candidates = source
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return candidates.filter { term in
            seen.insert(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
    }

    static func encode(_ terms: [String]) -> String {
        terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum DictationContextHints {
    static let maximumCount = 100

    static func prioritized(
        customWords: [String],
        modeHints: [String] = [],
        nearbyHints: [String] = [],
        learnedWords: [String] = [],
        limit: Int = maximumCount
    ) -> [String] {
        guard limit > 0 else { return [] }
        let boundedLimit = min(limit, maximumCount)
        let groups = [customWords, modeHints, nearbyHints, learnedWords]
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(boundedLimit)

        for group in groups {
            for candidate in group {
                let term = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { continue }
                let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: Locale(identifier: "en_US_POSIX"))
                guard seen.insert(key).inserted else { continue }
                result.append(term)
                if result.count == boundedLimit { return result }
            }
        }
        return result
    }
}
