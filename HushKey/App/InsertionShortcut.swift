import Carbon.HIToolbox

enum InsertionShortcut: String, CaseIterable, Identifiable {
    case optionShiftI
    case controlShiftI
    case optionShiftReturn

    static let `default` = InsertionShortcut.optionShiftI
    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionShiftI, .controlShiftI: UInt32(kVK_ANSI_I)
        case .optionShiftReturn: UInt32(kVK_Return)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionShiftI, .optionShiftReturn: UInt32(optionKey | shiftKey)
        case .controlShiftI: UInt32(controlKey | shiftKey)
        }
    }

    var label: String {
        switch self {
        case .optionShiftI: "⌥⇧I"
        case .controlShiftI: "⌃⇧I"
        case .optionShiftReturn: "⌥⇧↩"
        }
    }
}
