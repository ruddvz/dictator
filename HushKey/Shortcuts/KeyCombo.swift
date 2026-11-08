import AppKit
import Carbon.HIToolbox

/// One recorded shortcut: fn on its own, a key with modifiers, or an extra mouse button.
/// Stored as a short string (`"fn"`, `"opt+shift+k2"`, `"m3"`) so every shortcut setting
/// persists the same way; the names the old fixed menus saved still parse.
struct KeyCombo: Hashable, RawRepresentable, Identifiable {
    enum Trigger: Hashable {
        /// The fn (Globe) key on its own. Carbon can't register a lone modifier, so
        /// `FunctionKeyMonitor` watches it instead.
        case functionKey
        /// A virtual key code (`kVK_*`).
        case key(UInt32)
        /// `NSEvent.buttonNumber`: 2 is the middle button, 3 and up are side buttons.
        case mouse(Int)
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }

        init(_ flags: NSEvent.ModifierFlags) {
            var value: Modifiers = []
            if flags.contains(.control) { value.insert(.control) }
            if flags.contains(.option) { value.insert(.option) }
            if flags.contains(.shift) { value.insert(.shift) }
            if flags.contains(.command) { value.insert(.command) }
            self = value
        }

        var carbon: UInt32 {
            var value = 0
            if contains(.control) { value |= controlKey }
            if contains(.option) { value |= optionKey }
            if contains(.shift) { value |= shiftKey }
            if contains(.command) { value |= cmdKey }
            return UInt32(value)
        }

        var eventFlags: NSEvent.ModifierFlags {
            var value: NSEvent.ModifierFlags = []
            if contains(.control) { value.insert(.control) }
            if contains(.option) { value.insert(.option) }
            if contains(.shift) { value.insert(.shift) }
            if contains(.command) { value.insert(.command) }
            return value
        }

        /// macOS order: ⌃⌥⇧⌘.
        var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }

        fileprivate static let tokens: [(String, Modifiers)] = [
            ("ctrl", .control), ("opt", .option), ("shift", .shift), ("cmd", .command),
        ]
    }

    var trigger: Trigger
    var modifiers: Modifiers

    init(_ trigger: Trigger, modifiers: Modifiers = []) {
        self.trigger = trigger
        // fn and mouse buttons are recorded on their own.
        if case .key = trigger { self.modifiers = modifiers } else { self.modifiers = [] }
    }

    static let functionKey = KeyCombo(.functionKey)

    var id: String { rawValue }

    // MARK: Storage

    var rawValue: String {
        switch trigger {
        case .functionKey: return "fn"
        case .mouse(let button): return "m\(button)"
        case .key(let code):
            let mods = Modifiers.tokens.filter { modifiers.contains($0.1) }.map(\.0)
            return (mods + ["k\(code)"]).joined(separator: "+")
        }
    }

    init?(rawValue: String) {
        let raw = rawValue.trimmingCharacters(in: .whitespaces)
        if let legacy = Self.legacyNames[raw] { self = legacy; return }
        if raw == "fn" { self = .functionKey; return }
        if raw.hasPrefix("m"), let button = Int(raw.dropFirst()), button >= 2 {
            self.init(.mouse(button))
            return
        }
        var parts = raw.split(separator: "+").map(String.init)
        guard let last = parts.popLast(), last.hasPrefix("k"),
              let code = UInt32(last.dropFirst()), code <= 0x7F else { return nil }
        var mods: Modifiers = []
        for part in parts {
            guard let token = Modifiers.tokens.first(where: { $0.0 == part }) else { return nil }
            mods.insert(token.1)
        }
        self.init(.key(code), modifiers: mods)
    }

    /// The case names the fixed shortcut menus saved before the recorder.
    static let legacyNames: [String: KeyCombo] = [
        "optionShiftD": KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.option, .shift]),
        "controlShiftD": KeyCombo(.key(UInt32(kVK_ANSI_D)), modifiers: [.control, .shift]),
        "optionShiftReturn": KeyCombo(.key(UInt32(kVK_Return)), modifiers: [.option, .shift]),
        "optionShiftI": KeyCombo(.key(UInt32(kVK_ANSI_I)), modifiers: [.option, .shift]),
        "controlShiftI": KeyCombo(.key(UInt32(kVK_ANSI_I)), modifiers: [.control, .shift]),
        "optionShiftE": KeyCombo(.key(UInt32(kVK_ANSI_E)), modifiers: [.option, .shift]),
        "controlShiftE": KeyCombo(.key(UInt32(kVK_ANSI_E)), modifiers: [.control, .shift]),
        "optionShiftM": KeyCombo(.key(UInt32(kVK_ANSI_M)), modifiers: [.option, .shift]),
        "controlShiftM": KeyCombo(.key(UInt32(kVK_ANSI_M)), modifiers: [.control, .shift]),
    ]

    // MARK: Recording

    /// The shortcut a key press means, or nil for a lone modifier (those arrive as flagsChanged).
    /// fn is dropped as a modifier: macOS sets it on arrow and F-key presses too.
    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard !Self.modifierKeyCodes.contains(keyCode), keyCode <= 0x7F else { return nil }
        self.init(.key(UInt32(keyCode)), modifiers: Modifiers(modifierFlags))
    }

    init?(mouseButton: Int) {
        guard mouseButton >= 2 else { return nil }
        self.init(.mouse(mouseButton))
    }

    static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand), UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Option), UInt16(kVK_RightOption), UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock), UInt16(kVK_Function),
    ]

    // MARK: Using it

    var usesFunctionKey: Bool { trigger == .functionKey }
    var mouseButton: Int? { if case .mouse(let button) = trigger { button } else { nil } }
    var isKeyboard: Bool { if case .key = trigger { true } else { false } }

    /// The Carbon key code; fn reports its own code so callers can tell it apart.
    var keyCode: UInt32 {
        switch trigger {
        case .functionKey: UInt32(kVK_Function)
        case .key(let code): code
        case .mouse: 0
        }
    }

    var carbonModifiers: UInt32 { modifiers.carbon }

    var label: String {
        switch trigger {
        case .functionKey: return "fn"
        case .mouse(let button): return "Mouse \(button + 1)"
        case .key(let code): return modifiers.symbols + Self.keyName(for: code)
        }
    }

    // MARK: Key names

    static func keyName(for code: UInt32) -> String {
        if let special = specialKeyNames[Int(code)] { return special }
        if let typed = layoutCharacter(for: code) { return typed }
        return ansiKeyNames[Int(code)] ?? "Key \(code)"
    }

    static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in fKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()

    /// US names by key position, used when the keyboard layout can't be read.
    static let ansiKeyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]

    /// What the key types on the current keyboard layout, so AZERTY's A key reads "A", not "Q".
    private static func layoutCharacter(for code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.uppercased()
    }
}

// MARK: - Actions

/// Everything in HushKey a shortcut can trigger. Used to check a new shortcut against the others.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case dictation
    case pasteLast
    case editSelection
    case insertAgain
    case undoInsertion
    case silentCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .pasteLast: "Paste last dictation"
        case .editSelection: "Edit selected text by voice"
        case .insertAgain: "Paste again"
        case .undoInsertion: "Undo the last insertion"
        case .silentCapture: "Silent capture"
        }
    }

    /// Only dictation can use fn on its own; `FunctionKeyMonitor` watches it for hold and double-tap.
    var allowsFunctionKey: Bool { self == .dictation }
    /// Side mouse buttons are watched with an event monitor, wired for dictation and pasting.
    var allowsMouseButton: Bool { self == .dictation || self == .pasteLast }
}

// MARK: - Validation and conflicts

enum ShortcutProblem: Equatable {
    /// Can't be used at all, for example a bare letter that would swallow normal typing.
    case invalid(String)
    /// Already set for another HushKey action.
    case usedBy(ShortcutAction)
    /// A shortcut macOS or nearly every app relies on; taking it would break that everywhere.
    case reserved(String)
    /// Works, but something else on the Mac uses it too.
    case warning(String)

    /// Problems that stop the recorder from saving the shortcut.
    var blocksSaving: Bool {
        switch self {
        case .invalid, .usedBy, .reserved: true
        case .warning: false
        }
    }

    var message: String {
        switch self {
        case .invalid(let text), .reserved(let text), .warning(let text): text
        case .usedBy(let action): "Already used for \(action.title)."
        }
    }
}

enum ShortcutConflicts {
    /// The first problem with giving `combo` to `action`, given what the other actions use.
    /// Returns nil when the shortcut is free to use.
    static func problem(with combo: KeyCombo, for action: ShortcutAction,
                        assignments: [ShortcutAction: KeyCombo]) -> ShortcutProblem? {
        if let invalid = validity(of: combo, for: action) { return invalid }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && assignments[$0] == combo }) {
            return .usedBy(other)
        }
        if let known = systemShortcuts[combo] {
            return known.reserved ? .reserved("\(combo.label) is \(known.name). Pick another.")
                : .warning("\(combo.label) is also \(known.name). HushKey will take it.")
        }
        if let button = combo.mouseButton {
            return .warning(button == 2
                ? "Apps still get the click: middle click also opens links in new tabs."
                : "Apps still get the click: in browsers, side buttons also go back and forward.")
        }
        return nil
    }

    static func validity(of combo: KeyCombo, for action: ShortcutAction) -> ShortcutProblem? {
        switch combo.trigger {
        case .functionKey:
            return action.allowsFunctionKey ? nil : .invalid("fn on its own works only for dictation.")
        case .mouse:
            return action.allowsMouseButton ? nil : .invalid("Mouse buttons work for dictation and pasting.")
        case .key(let code):
            if code == UInt32(kVK_Escape), combo.modifiers.isEmpty {
                return .invalid("Escape cancels. Add ⌘, ⌥ or ⌃.")
            }
            let isFunctionRow = KeyCombo.functionKeyCodes.contains(Int(code))
            let hasCommandKey = !combo.modifiers.intersection([.command, .option, .control]).isEmpty
            if !isFunctionRow, !hasCommandKey {
                return .invalid("Add ⌘, ⌥ or ⌃ so normal typing still works.")
            }
            return nil
        }
    }

    private struct Known { let name: String; let reserved: Bool }

    private static func key(_ code: Int, _ modifiers: KeyCombo.Modifiers) -> KeyCombo {
        KeyCombo(.key(UInt32(code)), modifiers: modifiers)
    }

    /// Standard macOS shortcuts. Reserved ones would break copy, paste, quitting or switching apps
    /// in every app while HushKey runs; the rest are common enough to mention.
    private static let systemShortcuts: [KeyCombo: Known] = {
        var table: [KeyCombo: Known] = [:]
        let reserved: [(Int, KeyCombo.Modifiers, String)] = [
            (kVK_ANSI_C, .command, "Copy"), (kVK_ANSI_V, .command, "Paste"), (kVK_ANSI_X, .command, "Cut"),
            (kVK_ANSI_Z, .command, "Undo"), (kVK_ANSI_Z, [.command, .shift], "Redo"),
            (kVK_ANSI_A, .command, "Select All"), (kVK_ANSI_S, .command, "Save"),
            (kVK_ANSI_Q, .command, "Quit"), (kVK_ANSI_W, .command, "Close Window"),
            (kVK_ANSI_H, .command, "Hide"), (kVK_ANSI_M, .command, "Minimize"),
            (kVK_ANSI_N, .command, "New"), (kVK_ANSI_O, .command, "Open"), (kVK_ANSI_P, .command, "Print"),
            (kVK_ANSI_T, .command, "New Tab"), (kVK_ANSI_F, .command, "Find"),
            (kVK_ANSI_Comma, .command, "Settings"), (kVK_Tab, .command, "the app switcher"),
            (kVK_ANSI_Grave, .command, "the window switcher"), (kVK_Space, .command, "Spotlight"),
            (kVK_Escape, [.command, .option], "Force Quit"), (kVK_ANSI_Q, [.control, .command], "Lock Screen"),
            (kVK_ANSI_3, [.command, .shift], "a screenshot"), (kVK_ANSI_4, [.command, .shift], "a screenshot"),
            (kVK_ANSI_5, [.command, .shift], "the screenshot tool"),
        ]
        for (code, mods, name) in reserved { table[key(code, mods)] = Known(name: name, reserved: true) }
        let common: [(Int, KeyCombo.Modifiers, String)] = [
            (kVK_Space, .control, "the input source switcher"),
            (kVK_Space, [.control, .option], "the input source switcher"),
            (kVK_Space, [.control, .command], "the emoji picker"),
            (kVK_Space, [.command, .option], "Finder search"),
            (kVK_ANSI_F, [.control, .command], "Full Screen"),
            (kVK_ANSI_D, [.command, .option], "Dock hiding"),
            (kVK_UpArrow, .control, "Mission Control"), (kVK_DownArrow, .control, "App Exposé"),
            (kVK_LeftArrow, .control, "switching Spaces"), (kVK_RightArrow, .control, "switching Spaces"),
            (kVK_ANSI_V, [.command, .option], "Move in Finder"),
            (kVK_ANSI_V, [.command, .shift, .option], "Paste and Match Style"),
            (kVK_ANSI_Z, [.command, .option], "Redo in some apps"),
        ]
        for (code, mods, name) in common { table[key(code, mods)] = Known(name: name, reserved: false) }
        return table
    }()
}
