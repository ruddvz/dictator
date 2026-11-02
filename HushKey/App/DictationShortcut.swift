import Carbon.HIToolbox

enum DictationShortcut: String, CaseIterable, Identifiable {
    /// The fn (Globe) key: hold to talk, double-tap for hands-free. Watched by `FunctionKeyMonitor`,
    /// because Carbon hot keys cannot register a lone modifier.
    case fn
    case optionShiftD
    case controlShiftD
    case optionShiftReturn

    static let preferenceKey = "dictationShortcut"
    static let `default` = DictationShortcut.fn
    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionShiftD, .controlShiftD: UInt32(kVK_ANSI_D)
        case .optionShiftReturn: UInt32(kVK_Return)
        case .fn: UInt32(kVK_Function)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionShiftD, .optionShiftReturn: UInt32(optionKey | shiftKey)
        case .controlShiftD: UInt32(controlKey | shiftKey)
        case .fn: 0
        }
    }

    var label: String {
        switch self {
        case .optionShiftD: "⌥⇧D"
        case .controlShiftD: "⌃⇧D"
        case .optionShiftReturn: "⌥⇧↩"
        case .fn: "fn"
        }
    }

    var usesFunctionKey: Bool { self == .fn }

    var menuTitle: String { self == .fn ? "fn (Globe) key" : label }
}

enum DictationCaptureBehavior: String, CaseIterable, Identifiable {
    case hold = "Hold to talk"
    case toggle = "Press to toggle"

    static let preferenceKey = "dictationCaptureBehavior"
    var id: String { rawValue }
}
