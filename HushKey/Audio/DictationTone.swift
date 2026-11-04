import Foundation

/// How formal dictated text reads: capitals and full stops, or the looser style people use in
/// chat. Applied on this Mac after mode formatting; Code mode is never changed.
enum DictationTone: String, CaseIterable, Identifiable, Codable {
    case formal = "Formal"
    case casual = "Casual"
    case veryCasual = "Very casual"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .formal: "Capitals and full punctuation"
        case .casual: "Capitals, no final full stop"
        case .veryCasual: "Lower case, fewer full stops"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .formal: return text
        case .casual: return Self.droppingFinalFullStop(text)
        case .veryCasual: return Self.droppingSentenceFullStops(Self.lowercasingSentenceStarts(text))
        }
    }

    /// "See you soon." → "See you soon", leaving an ellipsis alone.
    static func droppingFinalFullStop(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return text }
        let trailing = text.reversed().prefix(while: \.isWhitespace).count
        var result = String(text.dropLast(trailing))
        result.removeLast()
        return result + String(text.suffix(trailing))
    }

    /// Lower-cases the first word of each sentence, except "I" (and I'm, I'll…) and words
    /// written in capitals such as acronyms.
    static func lowercasingSentenceStarts(_ text: String) -> String {
        var result = ""
        var atSentenceStart = true
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if atSentenceStart, character.isLetter {
                let wordEnd = text[index...].firstIndex { !($0.isLetter || $0 == "'" || $0 == "’") } ?? text.endIndex
                let word = String(text[index..<wordEnd])
                result += keepsCapital(word) ? word : word.prefix(1).lowercased() + word.dropFirst()
                index = wordEnd
                atSentenceStart = false
                continue
            }
            result.append(character)
            if ".!?\n".contains(character) { atSentenceStart = true }
            else if !character.isWhitespace, !"\"'“‘(".contains(character) { atSentenceStart = false }
            index = text.index(after: index)
        }
        return result
    }

    /// Removes full stops that end a sentence, keeping ellipses, decimals and ? or !.
    static func droppingSentenceFullStops(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (offset, character) in characters.enumerated() {
            if character == "." {
                let previous = offset > 0 ? characters[offset - 1] : " "
                let next = offset + 1 < characters.count ? characters[offset + 1] : " "
                let endsSentence = next.isWhitespace || next == "\"" || next == "”" || next == ")"
                if endsSentence, previous != ".", next != ".", previous.isLetter || previous.isNumber || previous == ")" {
                    continue
                }
            }
            result.append(character)
        }
        return result
    }

    private static func keepsCapital(_ word: String) -> Bool {
        let base = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? word
        if base == "I" { return true }
        return base.count > 1 && base == base.uppercased()
    }
}

/// Where a dictation is going, grouped the way people switch tone: friends, work chat, email,
/// everything else. Matched by the target app's bundle identifier only.
enum DictationContext: String, CaseIterable, Identifiable, Codable {
    case personal = "Personal messages"
    case work = "Work messages"
    case email = "Email"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .personal: "bubble.left.and.bubble.right"
        case .work: "briefcase"
        case .email: "envelope"
        case .other: "square.grid.2x2"
        }
    }

    /// Apps shown on the Style page for this context.
    var exampleApps: [String] {
        switch self {
        case .personal: ["Messages", "WhatsApp", "Telegram", "Signal", "Discord"]
        case .work: ["Slack", "Teams", "Mattermost"]
        case .email: ["Mail", "Outlook", "Spark", "Superhuman", "Mimestream"]
        case .other: ["Notes", "Docs", "Everything else"]
        }
    }

    /// What the preview card says, so each tone can be compared on a realistic message.
    var sample: String {
        switch self {
        case .personal: "Hey, are we still on for dinner tonight? I'm running about ten minutes late."
        case .work: "Quick update. The build is green and I'll ship the fix after lunch."
        case .email: "Hi Sam. Thanks for the notes. I've attached the revised plan for Friday."
        case .other: "Remember to book the train. Pack the charger and the blue folder."
        }
    }

    static func context(for bundleIdentifier: String?) -> DictationContext {
        let bundle = (bundleIdentifier ?? "").lowercased()
        guard !bundle.isEmpty else { return .other }
        let personal = ["com.apple.mobilesms", "whatsapp", "telegram", "signal", "discord", "messenger"]
        let work = ["slack", "teams", "mattermost"]
        let email = ["com.apple.mail", "outlook", "superhuman", "smartemail", "airmail", "mimestream"]
        if email.contains(where: bundle.contains) { return .email }
        if work.contains(where: bundle.contains) { return .work }
        if personal.contains(where: bundle.contains) { return .personal }
        return .other
    }
}

/// The tone chosen for each context. Formal everywhere until someone picks otherwise, so
/// existing dictation output does not change.
struct DictationToneSettings: Codable, Equatable {
    var tones: [DictationContext: DictationTone] = [:]

    func tone(for context: DictationContext) -> DictationTone { tones[context] ?? .formal }

    /// The tone for a dictation into `bundleIdentifier`; Code mode always keeps its text as is.
    func tone(forBundle bundleIdentifier: String?, mode: DictationMode) -> DictationTone {
        mode == .code ? .formal : tone(for: DictationContext.context(for: bundleIdentifier))
    }
}
