import AppKit

/// In-app recording shortcuts. HushKey never registers a global event tap.
enum CaptureShortcut: String, CaseIterable, Identifiable {
    case optionShiftM
    case controlShiftM
    case optionShiftReturn

    static let preferenceKey = "captureShortcut"
    static let `default` = CaptureShortcut.optionShiftM

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .optionShiftReturn: 36
        case .optionShiftM, .controlShiftM: 46
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .optionShiftM, .optionShiftReturn: [.option, .shift]
        case .controlShiftM: [.control, .shift]
        }
    }

    var label: String {
        switch self {
        case .optionShiftM: "⌥⇧M"
        case .controlShiftM: "⌃⇧M"
        case .optionShiftReturn: "⌥⇧↩"
        }
    }
}
