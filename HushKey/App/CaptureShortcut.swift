import AppKit
import Carbon.HIToolbox

/// In-app recording shortcuts. HushKey never registers a global event tap.
struct CaptureShortcut: RecordedShortcut {
    let combo: KeyCombo
    init(_ combo: KeyCombo) { self.combo = combo }

    static let action = ShortcutAction.silentCapture
    static let preferenceKey = "captureShortcut"
    static let `default` = CaptureShortcut(KeyCombo(.key(UInt32(kVK_ANSI_M)), modifiers: [.option, .shift]))

    /// Matched against local key events, which carry a `UInt16` code.
    var keyCode: UInt16 { UInt16(truncatingIfNeeded: combo.keyCode) }
    var modifiers: NSEvent.ModifierFlags { combo.modifiers.eventFlags }
}

/// Pastes the last dictation into the field it came from, from any app (Flow uses ⌃⌘V too).
/// It can be turned off; the menu bar item stays either way.
struct PasteLastShortcut: RecordedShortcut {
    let combo: KeyCombo
    init(_ combo: KeyCombo) { self.combo = combo }

    static let action = ShortcutAction.pasteLast
    static let preferenceKey = "pasteLastShortcut"
    static let `default` = PasteLastShortcut(KeyCombo(.key(UInt32(kVK_ANSI_V)), modifiers: [.control, .command]))
    /// Stored when the person clears the shortcut, so the default doesn't come back.
    static let offValue = "off"
}
