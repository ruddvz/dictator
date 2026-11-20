import Foundation

/// Formats spoken numbers, currency, percentages, clock time, units, CJK spacing,
/// and terminal/code sanitization into clean, polished text.
enum DictationSmartFormatter {
    private static let singleDigits: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9
    ]

    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let clockHours: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    private static let clockMinutes: [String: String] = [
        "o'clock": "00", "oclock": "00",
        "zero five": "05", "oh five": "05",
        "ten": "10", "fifteen": "15", "twenty": "20", "twenty-five": "25", "twenty five": "25",
        "thirty": "30", "thirty-five": "35", "thirty five": "35",
        "forty": "40", "forty-five": "45", "forty five": "45",
        "fifty": "50", "fifty-five": "55", "fifty five": "55"
    ]

    /// Idiomatic phrases starting with "one" that should not be converted to "1".
    private static let oneIdioms: Set<String> = [
        "one of", "one more", "one another", "one by one", "at one point",
        "which one", "this one", "that one", "the red one", "the blue one",
        "the first one", "the other one", "no one", "someone", "anyone", "everyone",
        "one day", "day one", "any one"
    ]

    /// Main entry point for formatting standard text in Natural, Message, and Email modes.
    static func format(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        result = formatClockTimes(result)
        result = formatCurrencies(result)
        result = formatPercentages(result)
        result = formatUnits(result)
        result = formatDecimals(result)
        result = formatQuantities(result)
        result = formatCJK(result)
        return result
    }

    /// Formats spoken clock times like "five thirty pm" -> "5:30 PM", "ten am" -> "10 AM", "twelve noon" -> "12:00 PM".
    static func formatClockTimes(_ text: String) -> String {
        var result = text
        // Spoken "twelve noon" / "twelve midnight"
        result = result.replacingOccurrences(of: #"(?i)\btwelve\s+noon\b"#, with: "12:00 PM", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)\btwelve\s+midnight\b"#, with: "12:00 AM", options: .regularExpression)

        // Hour + Minute + AM/PM: e.g. "five thirty pm" -> "5:30 PM", "9 45 am" -> "9:45 AM"
        let hourPattern = #"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[1-9]|1[0-2])"#
        let minuteWordPattern = #"(?:fifteen|twenty|twenty-five|twenty\s+five|thirty|thirty-five|thirty\s+five|forty|forty-five|forty\s+five|fifty|fifty-five|fifty\s+five|[0-5][0-9])"#
        let ampmPattern = #"(?:a\.?m\.?|p\.?m\.?|in\s+the\s+morning|in\s+the\s+afternoon|in\s+the\s+evening|at\s+night)"#

        let compoundRegex = try! NSRegularExpression(
            pattern: #"(?i)\b("# + hourPattern + #")\s+("# + minuteWordPattern + #")\s*("# + ampmPattern + #")\b"#)

        for match in compoundRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let hRange = Range(match.range(at: 1), in: result),
                  let mRange = Range(match.range(at: 2), in: result),
                  let ampmRange = Range(match.range(at: 3), in: result) else { continue }
            let hStr = String(result[hRange]).lowercased()
            let mStr = String(result[mRange]).lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let rawAmpm = String(result[ampmRange]).lowercased()

            let hourVal = clockHours[hStr] ?? Int(hStr)
            guard let hour = hourVal else { continue }

            let minStr: String
            if let mapped = clockMinutes[mStr] {
                minStr = mapped
            } else if let num = Int(mStr) {
                minStr = String(format: "%02d", num)
            } else {
                continue
            }

            let ampm: String
            if rawAmpm.contains("p") || rawAmpm.contains("afternoon") || rawAmpm.contains("evening") || rawAmpm.contains("night") {
                ampm = "PM"
            } else {
                ampm = "AM"
            }

            result.replaceSubrange(wholeRange, with: "\(hour):\(minStr) \(ampm)")
        }

        // Hour + AM/PM alone: e.g. "five pm" -> "5 PM", "10 am" -> "10 AM"
        let hourAloneRegex = try! NSRegularExpression(
            pattern: #"(?i)\b("# + hourPattern + #")\s*(a\.?m\.?|p\.?m\.?)\b"#)
        for match in hourAloneRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let hRange = Range(match.range(at: 1), in: result),
                  let ampmRange = Range(match.range(at: 2), in: result) else { continue }
            let hStr = String(result[hRange]).lowercased()
            let rawAmpm = String(result[ampmRange]).lowercased()
            guard let hour = clockHours[hStr] ?? Int(hStr) else { continue }
            let ampm = rawAmpm.hasPrefix("p") ? "PM" : "AM"
            result.replaceSubrange(wholeRange, with: "\(hour) \(ampm)")
        }

        return result
    }

    /// Formats spoken currencies:
    /// "twenty dollars and fifty cents" -> "$20.50"
    /// "twenty dollars" -> "$20", "fifty euros" -> "€50", "thirty pounds" -> "£30", "five hundred yen" -> "¥500"
    /// "five million dollars" -> "$5 million"
    static func formatCurrencies(_ text: String) -> String {
        var result = text

        let numberWord = #"(?:\d+|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred)"#
        let amountPattern = #"(?:"# + numberWord + #"(?:[-\s]+"# + numberWord + #")*)"#

        // 1. Dollars and cents: e.g. "twenty dollars and fifty cents" -> "$20.50"
        let dollarsAndCentsRegex = try! NSRegularExpression(
            pattern: #"(?i)\b("# + amountPattern + #")\s+(?:dollars|bucks)\s+and\s+("# + amountPattern + #")\s+cents?\b"#)
        for match in dollarsAndCentsRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let dRange = Range(match.range(at: 1), in: result),
                  let cRange = Range(match.range(at: 2), in: result) else { continue }
            let dStr = String(result[dRange])
            let cStr = String(result[cRange])
            guard let dVal = parseNumber(dStr), let cVal = parseNumber(cStr) else { continue }
            result.replaceSubrange(wholeRange, with: String(format: "$%d.%02d", dVal, cVal))
        }

        // 2. Large denominations: "five million dollars" -> "$5 million", "ten billion dollars" -> "$10 billion"
        let largeScaleRegex = try! NSRegularExpression(
            pattern: #"(?i)\b("# + amountPattern + #")\s+(million|billion|trillion)\s+(?:dollars|bucks)\b"#)
        for match in largeScaleRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let scaleRange = Range(match.range(at: 2), in: result) else { continue }
            let numStr = String(result[numRange])
            let scaleStr = String(result[scaleRange]).lowercased()
            guard let val = parseNumber(numStr) else { continue }
            result.replaceSubrange(wholeRange, with: "$\(val) \(scaleStr)")
        }

        // 3. Simple Dollars: "twenty dollars" -> "$20", "100 dollars" -> "$100"
        let simpleDollarRegex = try! NSRegularExpression(pattern: #"(?i)\b("# + amountPattern + #")\s+(?:dollars|bucks)\b"#)
        for match in simpleDollarRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result) else { continue }
            let numStr = String(result[numRange])
            guard let val = parseNumber(numStr) else { continue }
            result.replaceSubrange(wholeRange, with: "$\(val)")
        }

        // 4. Simple Cents: "fifty cents" -> "$0.50"
        let simpleCentsRegex = try! NSRegularExpression(pattern: #"(?i)\b("# + amountPattern + #")\s+cents?\b"#)
        for match in simpleCentsRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result) else { continue }
            let numStr = String(result[numRange])
            guard let val = parseNumber(numStr), val < 100 else { continue }
            result.replaceSubrange(wholeRange, with: String(format: "$0.%02d", val))
        }

        // 5. Euros, Pounds, Yen
        let currencySymbols: [(pattern: String, symbol: String)] = [
            (#"(?:euros?)"#, "€"),
            (#"(?:pounds?)"#, "£"),
            (#"(?:yen)"#, "¥")
        ]
        for (pattern, symbol) in currencySymbols {
            let regex = try! NSRegularExpression(pattern: #"(?i)\b("# + amountPattern + #")\s+"# + pattern + #"\b"#)
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let wholeRange = Range(match.range, in: result),
                      let numRange = Range(match.range(at: 1), in: result) else { continue }
                let numStr = String(result[numRange])
                guard let val = parseNumber(numStr) else { continue }
                result.replaceSubrange(wholeRange, with: "\(symbol)\(val)")
            }
        }

        return result
    }

    /// Formats spoken percentages: "twenty percent" -> "20%", "fifty point five percent" -> "50.5%"
    static func formatPercentages(_ text: String) -> String {
        var result = text
        let decimalPercentRegex = try! NSRegularExpression(
            pattern: #"(?i)\b([\p{L}\d-]+)\s+point\s+([\p{L}\d-]+)\s*(?:percent|percentage|per\s+cent)\b"#)
        for match in decimalPercentRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let wholeNumRange = Range(match.range(at: 1), in: result),
                  let fracNumRange = Range(match.range(at: 2), in: result) else { continue }
            let wholeStr = String(result[wholeNumRange])
            let fracStr = String(result[fracNumRange])
            guard let wholeVal = parseNumber(wholeStr), let fracVal = parseNumber(fracStr) else { continue }
            result.replaceSubrange(wholeRange, with: "\(wholeVal).\(fracVal)%")
        }

        let simplePercentRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(\d+(?:\.\d+)?|[\p{L}-]+)\s*(?:percent|percentage|per\s+cent)\b"#)
        for match in simplePercentRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result) else { continue }
            let numStr = String(result[numRange])
            if let directNum = Double(numStr) {
                let formatted = directNum.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(directNum))" : "\(directNum)"
                result.replaceSubrange(wholeRange, with: "\(formatted)%")
            } else if let val = parseNumber(numStr) {
                result.replaceSubrange(wholeRange, with: "\(val)%")
            }
        }

        return result
    }

    /// Formats spoken units:
    /// "twenty degrees celsius" -> "20°C"
    /// "ten gigabytes" -> "10 GB", "five megabytes" -> "5 MB"
    /// "sixty miles per hour" -> "60 mph"
    static func formatUnits(_ text: String) -> String {
        var result = text
        let unitMappings: [(pattern: String, replacement: (Int) -> String)] = [
            (#"(?i)\b([\p{L}\d-]+)\s+degrees?\s+celsius\b"#, { "\($0)°C" }),
            (#"(?i)\b([\p{L}\d-]+)\s+degrees?\s+fahrenheit\b"#, { "\($0)°F" }),
            (#"(?i)\b([\p{L}\d-]+)\s+degrees?\b"#, { "\($0)°" }),
            (#"(?i)\b([\p{L}\d-]+)\s+(?:gigabytes?|gb)\b"#, { "\($0) GB" }),
            (#"(?i)\b([\p{L}\d-]+)\s+(?:megabytes?|mb)\b"#, { "\($0) MB" }),
            (#"(?i)\b([\p{L}\d-]+)\s+(?:kilobytes?|kb)\b"#, { "\($0) KB" }),
            (#"(?i)\b([\p{L}\d-]+)\s+(?:terabytes?|tb)\b"#, { "\($0) TB" }),
            (#"(?i)\b([\p{L}\d-]+)\s+miles?\s+per\s+hour\b"#, { "\($0) mph" }),
            (#"(?i)\b([\p{L}\d-]+)\s+kilometers?\s+per\s+hour\b"#, { "\($0) km/h" })
        ]

        for (pattern, transform) in unitMappings {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let wholeRange = Range(match.range, in: result),
                      let numRange = Range(match.range(at: 1), in: result) else { continue }
                let numStr = String(result[numRange])
                guard let val = parseNumber(numStr) else { continue }
                result.replaceSubrange(wholeRange, with: transform(val))
            }
        }

        return result
    }

    /// Formats spoken decimals: "three point one four" -> "3.14", "zero point five" -> "0.5"
    static func formatDecimals(_ text: String) -> String {
        var result = text
        let decimalRegex = try! NSRegularExpression(
            pattern: #"(?i)\b([\p{L}\d-]+)\s+point\s+([\p{L}\d-]+(?:\s+[\p{L}\d-]+)*)\b"#)
        for match in decimalRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let wholeRange = Range(match.range, in: result),
                  let wholePartRange = Range(match.range(at: 1), in: result),
                  let fracPartRange = Range(match.range(at: 2), in: result) else { continue }
            let wholeStr = String(result[wholePartRange])
            let fracStr = String(result[fracPartRange])

            guard let wholeVal = parseNumber(wholeStr) else { continue }

            let fracWords = fracStr.split(separator: " ").map(String.init)
            var fracDigits = ""
            for word in fracWords {
                if let d = parseSingleDigit(word) {
                    fracDigits += "\(d)"
                } else if let num = Int(word) {
                    fracDigits += "\(num)"
                } else {
                    fracDigits = ""
                    break
                }
            }
            guard !fracDigits.isEmpty else { continue }
            result.replaceSubrange(wholeRange, with: "\(wholeVal).\(fracDigits)")
        }
        return result
    }

    /// Formats numerical quantities like "twenty five" -> "25", "one hundred and fifty" -> "150".
    /// Preserves common non-numeric idioms starting with "one".
    static func formatQuantities(_ text: String) -> String {
        var result = text

        // Compound numbers: e.g. "one hundred and fifty" -> "150", "two thousand twenty six" -> "2026"
        let compoundNumbers: [(pattern: String, transform: (NSTextCheckingResult, String) -> String?)] = [
            (
                #"(?i)\b(one|two|three|four|five|six|seven|eight|nine)\s+hundred(?:\s+and)?\s+([a-z-]+)\b"#,
                { match, str in
                    guard let hRange = Range(match.range(at: 1), in: str),
                          let tRange = Range(match.range(at: 2), in: str) else { return nil }
                    let hVal = singleDigits[String(str[hRange]).lowercased()] ?? 0
                    guard let tVal = parseNumber(String(str[tRange])), tVal < 100 else { return nil }
                    return "\(hVal * 100 + tVal)"
                }
            ),
            (
                #"(?i)\b(one|two|three|four|five|six|seven|eight|nine)\s+hundred\b"#,
                { match, str in
                    guard let hRange = Range(match.range(at: 1), in: str) else { return nil }
                    let hVal = singleDigits[String(str[hRange]).lowercased()] ?? 0
                    return "\(hVal * 100)"
                }
            ),
            (
                #"(?i)\b(two\s+thousand(?:\s+and)?)\s+([a-z-]+(?:\s+[a-z-]+)?)\b"#,
                { match, str in
                    guard let tRange = Range(match.range(at: 2), in: str) else { return nil }
                    guard let val = parseNumber(String(str[tRange])), val < 100 else { return nil }
                    return "\(2000 + val)"
                }
            ),
            (
                #"(?i)\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[-\s]+(one|two|three|four|five|six|seven|eight|nine)\b"#,
                { match, str in
                    guard let tenRange = Range(match.range(at: 1), in: str),
                          let unitRange = Range(match.range(at: 2), in: str) else { return nil }
                    let tenVal = tens[String(str[tenRange]).lowercased()] ?? 0
                    let unitVal = singleDigits[String(str[unitRange]).lowercased()] ?? 0
                    return "\(tenVal + unitVal)"
                }
            )
        ]

        for (pattern, transform) in compoundNumbers {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let wholeRange = Range(match.range, in: result) else { continue }
                if let replacement = transform(match, result) {
                    result.replaceSubrange(wholeRange, with: replacement)
                }
            }
        }

        return result
    }

    /// Normalizes spacing for Chinese, Japanese, and Korean (CJK) characters:
    /// removes unnatural spaces between CJK characters and around full-width punctuation.
    static func formatCJK(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        // CJK character regex
        let cjkChar = #"[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]"#
        let cjkSpaceRegex = try! NSRegularExpression(pattern: "(" + cjkChar + #")\s+("# + cjkChar + ")")

        // Apply repeatedly until all intra-CJK spaces are collapsed
        for _ in 0..<6 {
            let matches = cjkSpaceRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            if matches.isEmpty { break }
            result = cjkSpaceRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                            withTemplate: "$1$2")
        }

        // Collapse spaces before full-width punctuation
        result = result.replacingOccurrences(of: #"(?<=[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}])\s+([，。！？：；）》」』、])"#,
                                             with: "$1", options: .regularExpression)
        // Collapse spaces after full-width punctuation
        result = result.replacingOccurrences(of: #"([，。！？：；（《「『、])\s+(?=[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}])"#,
                                             with: "$1", options: .regularExpression)
        return result
    }

    /// Sanitizes text when writing in Code mode or targeting Terminal applications:
    /// converts typographic quotes/dashes to ASCII, removes accidental spaces in CLI flags/paths,
    /// and collapses newlines to avoid running half-dictated commands.
    static func formatCodeAndTerminal(_ text: String, isTerminal: Bool) -> String {
        var result = text
        // 1. Straighten curly quotes
        result = result.replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
        // 2. Straighten dashes
        result = result.replacingOccurrences(of: "[—–]", with: "-", options: .regularExpression)
        // 3. Fix spaces around CLI flags: e.g. "ls - la" -> "ls -la", "-- help" -> "--help"
        result = result.replacingOccurrences(of: #"(?<=\s|^)(-+)\s+([A-Za-z0-9])"#, with: "$1$2", options: .regularExpression)
        // 4. Fix spaces in file paths: "/ usr / bin" -> "/usr/bin", preserving space before leading slash in words
        result = result.replacingOccurrences(of: #"(?<=\s|^)/\s+([A-Za-z0-9_.-]+)"#, with: "/$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<=/[A-Za-z0-9_.-]{1,50})\s*/\s*([A-Za-z0-9_.-]+)"#, with: "/$1", options: .regularExpression)

        // 5. If terminal, collapse newlines into single spaces to avoid executing incomplete commands
        if isTerminal {
            result = result.replacingOccurrences(of: #"[ \t]*\n+[ \t]*"#, with: " ", options: .regularExpression)
        }
        return result
    }

    // MARK: - Number Parsing Helpers

    private static func parseSingleDigit(_ word: String) -> Int? {
        let key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return singleDigits[key] ?? Int(key)
    }

    private static func parseNumber(_ word: String) -> Int? {
        let trimmed = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let direct = Int(trimmed) { return direct }
        if let d = singleDigits[trimmed] { return d }
        if let t = teens[trimmed] { return t }
        if let tensVal = tens[trimmed] { return tensVal }
        if trimmed == "hundred" { return 100 }

        // Multi-token: "twenty-five", "twenty five", "one hundred", "one hundred and fifty"
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        if tokens.count == 2 {
            if let t = tens[tokens[0]], let u = singleDigits[tokens[1]] {
                return t + u
            }
            if let d = singleDigits[tokens[0]], tokens[1] == "hundred" {
                return d * 100
            }
        }
        if tokens.count == 3, let d = singleDigits[tokens[0]], tokens[1] == "hundred" {
            if let rem = parseNumber(tokens[2]) {
                return d * 100 + rem
            }
        }
        if tokens.count == 4, let d = singleDigits[tokens[0]], tokens[1] == "hundred", tokens[2] == "and" {
            if let rem = parseNumber(tokens[3]) {
                return d * 100 + rem
            }
        }
        return nil
    }
}
