import Carbon.HIToolbox

/// Types the last transcript or silent word again, from the Dictation or Silent Use page.
struct InsertionShortcut: RecordedShortcut {
    let combo: KeyCombo
    init(_ combo: KeyCombo) { self.combo = combo }

    static let action = ShortcutAction.insertAgain
    static let `default` = InsertionShortcut(KeyCombo(.key(UInt32(kVK_ANSI_I)), modifiers: [.option, .shift]))
}
