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

enum DictationSnippetExpander {
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
            .sorted { $0.0.count > $1.0.count }

        for (cue, replacement) in snippets {
            guard let expression = try? NSRegularExpression(
                pattern: "(?i)\\b\(NSRegularExpression.escapedPattern(for: cue))\\b([,.;:!?])?") else { continue }
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
}
