import Foundation

/// Gives a recognizer without contextual hints (Parakeet) the user's spellings of their words.
/// Apple Speech takes the same words as `contextualStrings` while it listens.
///
/// It only rewrites what clearly is the term: the same letters split across up to three words
/// ("hush key" → "HushKey", "Type Script" → "TypeScript"), the same word in another case when
/// the term has capitals ("github" → "GitHub"), or a capitalized name one letter away
/// ("Pria" → "Priya", for names of five letters or more).
enum DictationVocabularySnapper {
    static let maximumWindow = 3
    private static let builtInSpellingAliases = ["hushki": "HushKey"]

    static func apply(_ text: String, terms: [String]) -> String {
        let candidates = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { key(for: $0).count >= 3 }
            .sorted { key(for: $0).count > key(for: $1).count }
        guard !candidates.isEmpty, !text.isEmpty else { return text }

        var tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < tokens.count {
            var replaced = false
            for term in candidates {
                let termKey = key(for: term)
                for width in stride(from: min(maximumWindow, tokens.count - index), through: 1, by: -1) {
                    let window = Array(tokens[index..<(index + width)])
                    // Line breaks inside a window would be lost by the join.
                    guard !window.contains(where: { $0.contains("\n") || $0.isEmpty }) else { continue }
                    let core = window.map(strippedCore).joined(separator: " ")
                    guard matches(term: term, termKey: termKey, core: core, width: width) else { continue }
                    let leading = window.first.map(leadingPunctuation) ?? ""
                    let trailing = window.last.map(trailingPunctuation) ?? ""
                    tokens.replaceSubrange(index..<(index + width), with: [leading + term + trailing])
                    replaced = true
                    break
                }
                if replaced { break }
            }
            index += 1
        }
        return tokens.joined(separator: " ")
    }

    private static func matches(term: String, termKey: String, core: String, width: Int) -> Bool {
        guard core != term else { return false }
        let coreKey = key(for: core)
        if width == 1, builtInSpellingAliases[coreKey] == term { return true }
        if coreKey == termKey {
            // A split word is clearly the term; a single word only needs fixing for its capitals.
            return width > 1 || term != term.lowercased()
        }
        // A capitalized name with one letter wrong.
        guard width == 1, termKey.count >= 5, term.first?.isUppercase == true,
              core.first?.isUppercase == true, !term.contains(" ") else { return false }
        return editDistance(coreKey, termKey, limit: 1) <= 1
    }

    /// Letters and digits only, case- and accent-folded: "Hush-Key" and "hush key" share "hushkey".
    static func key(for value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func strippedCore(_ token: String) -> String {
        String(token.dropFirst(leadingPunctuation(token).count).dropLast(trailingPunctuation(token).count))
    }

    private static func leadingPunctuation(_ token: String) -> String {
        String(token.prefix { !$0.isLetter && !$0.isNumber })
    }

    private static func trailingPunctuation(_ token: String) -> String {
        let rest = token.drop { !$0.isLetter && !$0.isNumber }
        return String(rest.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
    }

    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
