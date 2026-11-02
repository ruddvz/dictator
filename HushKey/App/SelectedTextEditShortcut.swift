import Carbon.HIToolbox

enum SelectedTextEditShortcut: String, CaseIterable, Identifiable {
    case optionShiftE
    case controlShiftE

    static let preferenceKey = "selectedTextEditShortcut"
    static let `default` = SelectedTextEditShortcut.optionShiftE
    var id: String { rawValue }

    var keyCode: UInt32 { UInt32(kVK_ANSI_E) }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionShiftE: UInt32(optionKey | shiftKey)
        case .controlShiftE: UInt32(controlKey | shiftKey)
        }
    }

    var label: String {
        switch self {
        case .optionShiftE: "⌥⇧E"
        case .controlShiftE: "⌃⇧E"
        }
    }
}
