import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CryptoKit
import Observation

/// Explicit, opt-in insertion through the Accessibility selected-text attribute.
/// HushKey never writes to or replaces the clipboard.
@MainActor @Observable
final class TextInsertionService {
    private(set) var isEnabled = false
    private(set) var status = "Text insertion is off."
    private(set) var contextAccessStatus = "Nearby text hints are off."
    var shortcut: InsertionShortcut = InsertionShortcut(
        rawValue: UserDefaults.standard.string(forKey: "insertionShortcut") ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(shortcut.rawValue, forKey: "insertionShortcut")
            if isEnabled { registerShortcut() }
        }
    }
    @ObservationIgnored var onInsertShortcut: (() -> Void)?
    @ObservationIgnored var onUndoShortcut: (() -> Void)?
    @ObservationIgnored private let hotKey = GlobalHotKeyRegistration()
    @ObservationIgnored private let undoHotKey = GlobalHotKeyRegistration(id: 3)
    private var undoRecord: InsertionUndoRecord?

    private struct InsertionUndoRecord {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let element: AXUIElement
        let previousFingerprint: String
        let expectedFingerprint: String
        let selectedRange: CFRange
        let replacedText: String
        let insertedText: String
    }

    var canUndoLastInsertion: Bool { undoRecord != nil }
    var accessibilityAvailable: Bool { AXIsProcessTrusted() }

    func clearUndoRecord() { undoRecord = nil }

    @discardableResult
    func requestAccessibilityAccessForContext() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        contextAccessStatus = isTrusted
            ? "Accessibility is available. Nearby terms are read only when the opt-in is on and a supported text field is focused."
            : "Allow HushKey in System Settings → Privacy & Security → Accessibility, then check access again."
        return isTrusted
    }

    /// Reads a small, transient slice around the cursor only when the user has opted in.
    func nearbyContextHints() -> [String] {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              app.bundleIdentifier != "com.ruddvz.hushkey" else { return [] }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return [] }
        let focused = focusedValue as! AXUIElement
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(focused, &processIdentifier) == .success,
              processIdentifier == app.processIdentifier else { return [] }
        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, of: focused) ?? ""
        guard Self.isSupportedTextTarget(role: role, subrole: subrole),
              let selectedRange = selectedTextRange(of: focused), selectedRange.location >= 0,
              let value = stringAttribute(kAXValueAttribute, of: focused) else { return [] }

        let field = value as NSString
        guard selectedRange.location <= field.length else { return [] }
        let start = max(0, selectedRange.location - 220)
        let end = min(field.length, selectedRange.location + selectedRange.length + 100)
        guard end > start else { return [] }
        let nearby = field.substring(with: NSRange(location: start, length: end - start))
        return DictationContextHintExtractor.extract(from: nearby)
    }

    func enable() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        isEnabled = trusted
        if trusted {
            registerShortcut()
            let undoStatus = undoHotKey.register(keyCode: UInt32(kVK_ANSI_U),
                                                 modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
                self?.onUndoShortcut?()
            }
            if undoStatus != noErr {
                status = "Insertion is enabled, but ⌥⇧U could not be registered for safe undo."
            }
        } else {
            status = "Allow HushKey in System Settings → Privacy & Security → Accessibility, then enable again."
        }
    }

    func disable() {
        isEnabled = false
        hotKey.unregister()
        undoHotKey.unregister()
        undoRecord = nil
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

        let originalValue = stringAttribute(kAXValueAttribute, of: focused)
        let originalRange = selectedTextRange(of: focused)
        let possibleUndo = Self.makeUndoRecord(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            element: focused,
            originalValue: originalValue,
            selectedRange: originalRange,
            insertedText: text)

        guard AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            status = "The focused app declined safe insertion. Nothing was inserted."
            return false
        }
        if let possibleUndo,
           stringAttribute(kAXValueAttribute, of: focused).map(Self.fingerprint) == possibleUndo.expectedFingerprint {
            undoRecord = possibleUndo
            status = "Inserted once. Press ⌥⇧U now to undo while this field stays focused and unchanged."
        } else {
            undoRecord = nil
            status = "Inserted once into the current text selection. This field does not expose a safe undo record."
        }
        return true
    }

    @discardableResult
    func undoLastInsertion() -> Bool {
        guard let record = undoRecord else {
            status = "There is no recent insertion to undo."
            return false
        }
        guard AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == record.processIdentifier else {
            undoRecord = nil
            status = "Return to the same app and field before undoing. Nothing was changed."
            return false
        }
        let systemWide = AXUIElementCreateSystemWide()
        var currentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &currentValue) == .success,
              let currentValue, CFEqual(record.element, currentValue),
              stringAttribute(kAXValueAttribute, of: record.element).map(Self.fingerprint) == record.expectedFingerprint,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == record.bundleIdentifier else {
            undoRecord = nil
            status = "This field changed or lost focus after insertion. Nothing was undone."
            return false
        }

        var replacementRange = CFRange(location: record.selectedRange.location,
                                       length: (record.insertedText as NSString).length)
        guard let rangeValue = AXValueCreate(.cfRange, &replacementRange),
              AXUIElementSetAttributeValue(record.element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
              AXUIElementSetAttributeValue(record.element, kAXSelectedTextAttribute as CFString,
                                           record.replacedText as CFString) == .success,
              stringAttribute(kAXValueAttribute, of: record.element).map(Self.fingerprint) == record.previousFingerprint else {
            undoRecord = nil
            status = "The app could not safely restore the previous text."
            return false
        }
        undoRecord = nil
        status = "Undid the last HushKey insertion."
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
            ? "Enabled. Insert with \(shortcut.label); undo immediately with ⌥⇧U while the same field stays focused."
            : "Could not register \(shortcut.label) (system status \(result))."
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    private static func makeUndoRecord(processIdentifier: pid_t, bundleIdentifier: String?, element: AXUIElement,
                                       originalValue: String?, selectedRange: CFRange?, insertedText: String)
        -> InsertionUndoRecord?
    {
        guard let originalValue, let selectedRange,
              originalValue.utf16.count <= 20_000,
              selectedRange.location >= 0, selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= originalValue.utf16.count else { return nil }
        let original = originalValue as NSString
        let selection = NSRange(location: selectedRange.location, length: selectedRange.length)
        let replaced = original.substring(with: selection)
        let expected = original.replacingCharacters(in: selection, with: insertedText)
        return InsertionUndoRecord(processIdentifier: processIdentifier, bundleIdentifier: bundleIdentifier,
                                   element: element, previousFingerprint: fingerprint(originalValue),
                                   expectedFingerprint: fingerprint(expected),
                                   selectedRange: selectedRange, replacedText: replaced, insertedText: insertedText)
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
