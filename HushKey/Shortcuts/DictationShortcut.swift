import Carbon.HIToolbox

/// A recorded shortcut for one action. It keeps the API the fixed menus had (`rawValue`,
/// `keyCode`, `carbonModifiers`, `label`) so callers didn't change when the recorder came in,
/// and still reads the names those menus saved.
protocol RecordedShortcut: Hashable, RawRepresentable, Identifiable where RawValue == String {
    var combo: KeyCombo { get }
    init(_ combo: KeyCombo)
    static var action: ShortcutAction { get }
    static var `default`: Self { get }
}

extension RecordedShortcut {
    init?(rawValue: String) {
        guard let combo = KeyCombo(rawValue: rawValue),
              ShortcutConflicts.validity(of: combo, for: Self.action) == nil else { return nil }
        self.init(combo)
    }

    var rawValue: String { combo.rawValue }
    var id: String { rawValue }
    var keyCode: UInt32 { combo.keyCode }
    var carbonModifiers: UInt32 { combo.carbonModifiers }
    var label: String { combo.label }
}

struct DictationShortcut: RecordedShortcut {
    let combo: KeyCombo
    init(_ combo: KeyCombo) { self.combo = combo }

    static let action = ShortcutAction.dictation
    static let preferenceKey = "dictationShortcut"
    /// The fn (Globe) key: hold to talk, double-tap for hands-free. Watched by `FunctionKeyMonitor`,
    /// because Carbon hot keys cannot register a lone modifier.
    static let fn = DictationShortcut(.functionKey)
    static let `default` = DictationShortcut.fn

    var usesFunctionKey: Bool { combo.usesFunctionKey }
    var mouseButton: Int? { combo.mouseButton }
    var menuTitle: String { usesFunctionKey ? "fn (Globe) key" : label }
}

enum DictationCaptureBehavior: String, CaseIterable, Identifiable {
    case hold = "Hold to talk"
    case toggle = "Press to toggle"

    static let preferenceKey = "dictationCaptureBehavior"
    var id: String { rawValue }
}
