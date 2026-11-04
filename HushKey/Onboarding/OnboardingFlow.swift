import AppKit
import Foundation

// The 60-second first run: permissions, a mic test, the shortcut, one practice dictation and a
// closing whisper. Everything here is plain state so the steps and their rules can be tested
// without a window, a microphone or a permission prompt.

/// The first run's steps, in order.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case permissions
    case micTest
    case shortcut
    case practice
    case whisper

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .permissions: "Two permissions"
        case .micTest: "Check your microphone"
        case .shortcut: "Your dictation key"
        case .practice: "Try one dictation"
        case .whisper: "Now whisper it"
        }
    }

    /// The short name in the step dots, for VoiceOver.
    var shortName: String {
        switch self {
        case .permissions: "Permissions"
        case .micTest: "Microphone"
        case .shortcut: "Shortcut"
        case .practice: "Practice"
        case .whisper: "Whisper"
        }
    }
}

/// Where the first run is, and how it moves. Skipping a step is always allowed.
struct OnboardingFlow: Equatable, Sendable {
    private(set) var step: OnboardingStep = .permissions
    /// Steps whose check passed (permission granted, voice heard, key pressed, and so on).
    private(set) var completed: Set<OnboardingStep> = []
    private(set) var isFinished = false

    init(step: OnboardingStep = .permissions) {
        self.step = step
    }

    var index: Int { step.rawValue }
    var count: Int { OnboardingStep.allCases.count }
    var isFirst: Bool { step == OnboardingStep.allCases.first }
    var isLast: Bool { step == OnboardingStep.allCases.last }
    var progress: Double { Double(index + 1) / Double(count) }
    var currentStepPassed: Bool { completed.contains(step) }

    /// The main button: a plain "Continue" once the step's check passed, otherwise a skip.
    var continueTitle: String {
        if isLast { return currentStepPassed ? "Finish" : "Finish without it" }
        return currentStepPassed ? "Continue" : "Skip this step"
    }

    mutating func markPassed(_ step: OnboardingStep) {
        completed.insert(step)
    }

    /// Moves on; on the last step this finishes the run instead.
    mutating func advance() {
        guard !isFinished else { return }
        if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next }
        else { isFinished = true }
    }

    mutating func back() {
        guard !isFinished, let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Jumps to a step already reached or passed, from the step dots.
    mutating func go(to target: OnboardingStep) {
        guard !isFinished, target.rawValue <= step.rawValue || completed.contains(target) else { return }
        step = target
    }
}

/// Remembers whether the first run was finished or skipped, in the app's existing
/// `UserDefaults` settings, so it shows only once on its own.
struct OnboardingRecord {
    enum Outcome: String { case completed, skipped }

    static let outcomeKey = "onboardingOutcome"
    /// Set by `AppModel` after any finished dictation: someone who has dictated already has set up.
    static let firstDictationKey = "completedFirstDictation"

    var defaults: UserDefaults = .standard

    var outcome: Outcome? {
        defaults.string(forKey: Self.outcomeKey).flatMap(Outcome.init(rawValue:))
    }

    /// Show the first run on launch only to someone who has neither seen it nor dictated yet,
    /// so people upgrading from an earlier HushKey aren't walked through setup again.
    var showsOnLaunch: Bool {
        outcome == nil && !defaults.bool(forKey: Self.firstDictationKey)
    }

    func record(_ outcome: Outcome) {
        // Finishing after an earlier skip upgrades the record; a later skip never downgrades it.
        if outcome == .skipped, self.outcome == .completed { return }
        defaults.set(outcome.rawValue, forKey: Self.outcomeKey)
    }
}

/// The two permissions the first run asks for, with the System Settings pane for each.
enum OnboardingPermission: CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    var reason: String {
        switch self {
        case .microphone: "Hears you only while you hold the dictation key. Audio stays on this Mac."
        case .accessibility: "Lets the fn key work in any app, and types your words where the cursor is."
        }
    }

    var settingsURL: URL {
        switch self {
        case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }

    enum Status: Equatable, Sendable {
        case granted
        /// macOS hasn't asked yet; for the microphone, HushKey can show the system prompt.
        case notAsked
        /// Turned off, or restricted: only System Settings can change it.
        case off
    }

    enum Action: Equatable, Sendable {
        /// Show the macOS prompt (microphone, first time only).
        case request
        case openSettings
    }

    /// What the card's button does for a status; nil when there's nothing left to do.
    func action(for status: Status) -> Action? {
        switch (self, status) {
        case (_, .granted): nil
        case (.microphone, .notAsked): .request
        default: .openSettings
        }
    }

    func buttonTitle(for status: Status) -> String? {
        switch action(for: status) {
        case .request: "Allow"
        case .openSettings: "Open Settings"
        case nil: nil
        }
    }

    func statusLine(for status: Status) -> String {
        switch (self, status) {
        case (_, .granted): "On"
        case (.microphone, .notAsked): "Not asked yet"
        case (.microphone, .off): "Off. Turn on HushKey in Microphone settings."
        case (.accessibility, .notAsked): "Not on yet. Turn on HushKey in Accessibility settings, then come back."
        case (.accessibility, .off): "Off. Turn on HushKey in Accessibility settings, then come back."
        }
    }

    static func allGranted(_ statuses: [OnboardingPermission: Status]) -> Bool {
        allCases.allSatisfy { statuses[$0] == .granted }
    }
}

/// Decides the mic test has heard a voice: a few frames above a speaking level, so a single
/// click or bump doesn't count.
struct MicCheck: Equatable, Sendable {
    static let speakingLevel: Float = 0.12
    static let framesNeeded = 6

    private(set) var loudFrames = 0
    private(set) var peak: Float = 0
    var heardVoice: Bool { loudFrames >= Self.framesNeeded }

    mutating func ingest(_ level: Float) {
        peak = max(peak, level)
        if level >= Self.speakingLevel { loudFrames += 1 }
    }

    mutating func reset() { self = MicCheck() }
}

/// The dictation shortcut as keycaps, and which of them are held right now.
struct ShortcutKeycaps: Equatable, Sendable {
    struct Cap: Equatable, Identifiable, Sendable {
        var id: String { glyph }
        var glyph: String
        /// The modifier this cap stands for; nil for the final, ordinary key.
        var modifier: NSEvent.ModifierFlags.RawValue?
    }

    let shortcut: DictationShortcut
    let caps: [Cap]

    init(_ shortcut: DictationShortcut) {
        self.shortcut = shortcut
        caps = KeycapShortcut.keys(in: shortcut.label).map { glyph in
            Cap(glyph: glyph, modifier: Self.modifier(for: glyph)?.rawValue)
        }
    }

    static func modifier(for glyph: String) -> NSEvent.ModifierFlags? {
        switch glyph {
        case "fn": .function
        case "⌥": .option
        case "⇧": .shift
        case "⌃": .control
        case "⌘": .command
        default: nil
        }
    }

    /// The caps to light, from the held modifier flags and whether the shortcut's own key is down.
    func lit(flags: NSEvent.ModifierFlags, keyDown: Bool) -> Set<String> {
        var lit = Set<String>()
        for cap in caps {
            if let raw = cap.modifier {
                if flags.contains(NSEvent.ModifierFlags(rawValue: raw)) { lit.insert(cap.glyph) }
            } else if keyDown {
                lit.insert(cap.glyph)
            }
        }
        return lit
    }

    /// Every cap is held at once: the whole shortcut was pressed.
    func isComplete(_ lit: Set<String>) -> Bool {
        caps.allSatisfy { lit.contains($0.glyph) }
    }
}

/// The practice step's before and after: which spoken words cleanup took out.
enum CleanupPreview {
    /// The line the practice step asks for, and what HushKey's rules make of it.
    static let practicePhrase = "Um, I'll be there at four, no, five."

    /// Runs the same rules dictation uses (spoken corrections, then fillers), for the
    /// "show me without speaking" example.
    static func clean(_ text: String) -> String {
        DictationLocalCleanup.removeFillers(from: DictationBacktrack.apply(to: text))
    }

    struct Word: Equatable, Sendable {
        var text: String
        var removed: Bool
    }

    /// The spoken words in order, each marked removed when the cleaned text doesn't keep it.
    /// A longest-common-subsequence match on bare lowercase words, so punctuation and the
    /// capitals cleanup restores don't count as changes.
    static func words(raw: String, cleaned: String) -> [Word] {
        let spoken = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        let a = spoken.map(bare), b = kept.map(bare)
        guard !a.isEmpty else { return [] }
        // lengths[i][j]: the longest common run of a[i...] and b[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var result: [Word] = []
        var i = 0, j = 0
        while i < a.count {
            if j < b.count, a[i] == b[j] {
                result.append(Word(text: spoken[i], removed: false))
                i += 1; j += 1
            } else if j < b.count, lengths[i][j + 1] > lengths[i + 1][j] {
                j += 1
            } else {
                result.append(Word(text: spoken[i], removed: true))
                i += 1
            }
        }
        return result
    }

    private static func bare(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" }
    }
}

/// The closing whisper test: did HushKey catch "a whisper is enough"?
enum WhisperCheck {
    static let phrase = "A whisper is enough."

    /// True when most of the phrase's words came through, in any case or punctuation.
    static func matches(_ transcript: String) -> Bool {
        let heard = Set(words(transcript))
        let wanted = words(phrase)
        let found = wanted.filter(heard.contains).count
        return found >= wanted.count - 1 && heard.contains("whisper")
    }

    /// How the whisper's loudness compares with the speaking voice from the mic test, as a
    /// rounded percentage; nil without both readings.
    static func relativeLoudness(whisperPeak: Float, speakingPeak: Float) -> Int? {
        guard whisperPeak > 0, speakingPeak > 0.01 else { return nil }
        let percent = Int((Double(whisperPeak / speakingPeak) * 100).rounded())
        return min(percent, 100)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }
}
