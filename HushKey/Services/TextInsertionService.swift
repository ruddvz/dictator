import AppKit
import ApplicationServices
import Observation

/// Explicit, opt-in insertion through the Accessibility selected-text attribute.
/// HushKey never writes to or replaces the clipboard.
@MainActor @Observable
final class TextInsertionService {
    private(set) var isEnabled = false
    private(set) var status = "Text insertion is off."
    var shortcut: InsertionShortcut = InsertionShortcut(
        rawValue: UserDefaults.standard.string(forKey: "insertionShortcut") ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(shortcut.rawValue, forKey: "insertionShortcut")
            if isEnabled { registerShortcut() }
        }
    }
    @ObservationIgnored var onInsertShortcut: (() -> Void)?
    @ObservationIgnored private let hotKey = GlobalHotKeyRegistration()

    func enable() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        isEnabled = trusted
        if trusted {
            registerShortcut()
        } else {
            status = "Allow HushKey in System Settings → Privacy & Security → Accessibility, then enable again."
        }
    }

    func disable() {
        isEnabled = false
        hotKey.unregister()
        status = "Text insertion is off."
    }

    func report(_ message: String) { status = message }

    @discardableResult
    func insert(_ text: String) -> Bool {
        guard isEnabled else { status = "Enable text insertion first."; return false }
        guard AXIsProcessTrusted() else {
            isEnabled = false
            status = "Accessibility access is unavailable. Text was not inserted."
            return false
        }
        guard !text.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              app.bundleIdentifier != "com.ruddvz.hushkey" else {
            status = "Focus a text field in another app first."
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            status = "Could not inspect the focused control. Nothing was inserted."
            return false
        }
        let focused = focusedValue as! AXUIElement
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == app.processIdentifier else {
            status = "The focused control changed. Nothing was inserted."
            return false
        }

        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, of: focused) ?? ""
        guard Self.isSupportedTextTarget(role: role, subrole: subrole) else {
            status = subrole == kAXSecureTextFieldSubrole as String
                ? "Secure and password fields are never supported."
                : "This focused control is not a supported text field."
            return false
        }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            status = "This field does not support safe selected-text insertion. Nothing was inserted."
            return false
        }

        // Re-check the frontmost process and exact focused element immediately before mutation.
        var currentValue: CFTypeRef?
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &currentValue) == .success,
              let currentValue, CFEqual(focused, currentValue) else {
            status = "Focus changed before insertion. Nothing was inserted."
            return false
        }

        guard AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            status = "The focused app declined safe insertion. Nothing was inserted."
            return false
        }
        status = "Inserted once into the current text selection."
        return true
    }

    static func isSupportedTextTarget(role: String, subrole: String) -> Bool {
        guard subrole != (kAXSecureTextFieldSubrole as String) else { return false }
        return [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
    }

    private func registerShortcut() {
        let result = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.onInsertShortcut?()
        }
        status = result == noErr
            ? "Enabled. Focus a supported text field in another app, then press \(shortcut.label) to insert the current output once."
            : "Could not register \(shortcut.label) (system status \(result))."
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
