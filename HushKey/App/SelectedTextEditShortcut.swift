import Carbon.HIToolbox

struct SelectedTextEditShortcut: RecordedShortcut {
    let combo: KeyCombo
    init(_ combo: KeyCombo) { self.combo = combo }

    static let action = ShortcutAction.editSelection
    static let preferenceKey = "selectedTextEditShortcut"
    static let `default` = SelectedTextEditShortcut(KeyCombo(.key(UInt32(kVK_ANSI_E)), modifiers: [.option, .shift]))
}
