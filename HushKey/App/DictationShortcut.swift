import Carbon.HIToolbox

enum DictationShortcut: String, CaseIterable, Identifiable {
    case optionShiftD
    case controlShiftD
    case optionShiftReturn

    static let preferenceKey = "dictationShortcut"
    static let `default` = DictationShortcut.optionShiftD
    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionShiftD, .controlShiftD: UInt32(kVK_ANSI_D)
        case .optionShiftReturn: UInt32(kVK_Return)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionShiftD, .optionShiftReturn: UInt32(optionKey | shiftKey)
        case .controlShiftD: UInt32(controlKey | shiftKey)
        }
    }

    var label: String {
        switch self {
        case .optionShiftD: "⌥⇧D"
        case .controlShiftD: "⌃⇧D"
        case .optionShiftReturn: "⌥⇧↩"
        }
    }
}

enum DictationCaptureBehavior: String, CaseIterable, Identifiable {
    case hold = "Hold to talk"
    case toggle = "Press to toggle"

    static let preferenceKey = "dictationCaptureBehavior"
    var id: String { rawValue }
}
