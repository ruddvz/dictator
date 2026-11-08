import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CryptoKit
import Observation
import os

enum DirectInsertionVerification: Equatable {
    case verified
    case unchanged
    case changedUnexpectedly
}

/// Explicit, opt-in insertion through the Accessibility selected-text attribute.
/// HushKey never writes to or replaces the clipboard.
@MainActor @Observable
final class TextInsertionService {
    struct PasteTarget {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let applicationName: String
        let element: AXUIElement
        let role: String
        let subrole: String
        let fieldValue: String
        let selectedRange: CFRange
    }

    enum PasteOutcome: Equatable {
        case inserted
        /// Cmd-V was sent, but the same field did not expose the exact expected text in time.
        case unconfirmed
        /// No paste was sent because the target could not be safely validated.
        case unavailable
    }

    struct InsertionTarget {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let applicationName: String
        let element: AXUIElement
        let fieldValue: String
        let selectedRange: CFRange
    }

    struct SelectedTextTarget {
        let insertionTarget: InsertionTarget
        let selectedText: String
    }

    private(set) var isEnabled = false
    /// Callers must not retry when an accessibility edit may have changed the field but
    /// read-back could not confirm the exact result.
    private(set) var requiresReviewAfterInsertion = false
    /// Whether the last delivery was read back from the field. False after a paste HushKey
    /// couldn't confirm, so the pill says "Pasted" rather than claiming "Typed".
    private(set) var lastDeliveryVerified = true
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var exposedProcesses: Set<pid_t> = []
    /// Paste through the clipboard in apps that refuse direct typing; the clipboard is restored.
    var allowsPasteFallback = UserDefaults.standard.object(forKey: "allowsPasteFallback") as? Bool ?? true {
        didSet { UserDefaults.standard.set(allowsPasteFallback, forKey: "allowsPasteFallback") }
    }
    private(set) var status = "Typing is off."
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
        exposeWebContent(of: app)

        guard let focused = focusedElement(expectedProcessIdentifier: app.processIdentifier) else { return [] }
        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, of: focused) ?? ""
        var isPassword: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXIsPassword" as CFString, &isPassword) == .success,
           let isPassword = isPassword as? Bool, isPassword {
            return []
        }
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

    /// Captures an explicit, supported text target while another app is frontmost.
    /// The snapshot is kept only in memory and is revalidated before later insertion.
    func captureInsertionTarget() -> InsertionTarget? {
        guard isEnabled, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              app.bundleIdentifier != "com.ruddvz.hushkey" else { return nil }
        exposeWebContent(of: app)
        guard let focused = focusedElement(expectedProcessIdentifier: app.processIdentifier) else { return nil }
        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, of: focused) ?? ""
        var isPassword: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXIsPassword" as CFString, &isPassword) == .success,
           let isPassword = isPassword as? Bool, isPassword {
            return nil
        }
        guard Self.isSupportedTextTarget(role: role, subrole: subrole),
              let fieldValue = stringAttribute(kAXValueAttribute, of: focused),
              fieldValue.utf16.count <= 20_000,
              let selectedRange = selectedTextRange(of: focused),
              selectedRange.location <= fieldValue.utf16.count,
              selectedRange.length <= fieldValue.utf16.count - selectedRange.location else { return nil }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return nil }
        return InsertionTarget(processIdentifier: app.processIdentifier,
                               bundleIdentifier: app.bundleIdentifier,
                               applicationName: app.localizedName ?? "the original app",
                               element: focused,
                               fieldValue: fieldValue,
                               selectedRange: selectedRange)
    }

    /// Captures only a non-empty selection in an explicitly supported text field.
    /// The selection and its containing field stay in memory and are revalidated before Apply.
    func captureSelectedTextTarget() -> SelectedTextTarget? {
        guard let target = captureInsertionTarget(),
              let selectedText = Self.selectedText(in: target.fieldValue, range: target.selectedRange),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedText.count <= 12_000 else { return nil }
        return SelectedTextTarget(insertionTarget: target, selectedText: selectedText)
    }

    private static let enabledKey = "typesIntoApps"

    /// Turns typing back on at launch, and once Accessibility is granted, unless the user turned
    /// it off. It is on by default, so a focused text field gets the text without a visit to Settings.
    func restore() {
        guard !isEnabled, UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true,
              AXIsProcessTrusted() else { return }
        enable(prompting: false)
    }

    func enable(prompting: Bool = true) {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: prompting] as CFDictionary)
        isEnabled = trusted
        if prompting { UserDefaults.standard.set(true, forKey: Self.enabledKey) }
        if trusted {
            watchActivations()
            registerShortcut()
            let undoStatus = undoHotKey.register(keyCode: UInt32(kVK_ANSI_U),
                                                 modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
                self?.onUndoShortcut?()
            }
            if undoStatus != noErr {
                status = "Typing is on, but ⌥⇧U couldn’t be set up for undo."
            }
        } else {
            status = "Allow HushKey in System Settings → Privacy & Security → Accessibility, then enable again."
        }
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        isEnabled = false
        hotKey.unregister()
        undoHotKey.unregister()
        undoRecord = nil
        status = "Typing is off."
    }

    func report(_ message: String) { status = message }

    @discardableResult
    func insert(_ text: String) -> Bool {
        requiresReviewAfterInsertion = false
        lastDeliveryVerified = true
        guard isEnabled else { status = "Turn on typing first."; return false }
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

        guard let focused = focusedElement(expectedProcessIdentifier: app.processIdentifier) else {
            status = "Could not inspect the focused control. Nothing was inserted."
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
        guard let current = focusedElement(expectedProcessIdentifier: app.processIdentifier) else {
            status = "Focus changed before insertion. Nothing was inserted."
            return false
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              CFEqual(focused, current) else {
            status = "Focus changed before insertion. Nothing was inserted."
            return false
        }

        return performInsertion(text, app: app, element: focused,
                                originalValue: stringAttribute(kAXValueAttribute, of: focused),
                                selectedRange: selectedTextRange(of: focused))
    }

    /// Returns to the captured app only after an explicit user action, then verifies the
    /// exact field and selection before replacing text. A stale target always fails closed.
    @discardableResult
    func insert(_ text: String, into target: InsertionTarget) async -> Bool {
        requiresReviewAfterInsertion = false
        lastDeliveryVerified = true
        guard isEnabled, AXIsProcessTrusted() else {
            isEnabled = false
            status = "Accessibility access is unavailable. Text was not inserted."
            return false
        }
        guard !text.isEmpty,
              let app = NSRunningApplication(processIdentifier: target.processIdentifier),
              !app.isTerminated,
              app.bundleIdentifier == target.bundleIdentifier else {
            status = "The original app is no longer available. Nothing was inserted."
            return false
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            guard app.activate(options: []) else {
                status = "Could not return to \(target.applicationName). Nothing was inserted."
                return false
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let focused = focusedElement(expectedProcessIdentifier: target.processIdentifier),
              CFEqual(target.element, focused),
              let role = stringAttribute(kAXRoleAttribute, of: focused),
              Self.isSupportedTextTarget(role: role, subrole: stringAttribute(kAXSubroleAttribute, of: focused) ?? ""),
              let currentValue = stringAttribute(kAXValueAttribute, of: focused),
              let currentRange = selectedTextRange(of: focused),
              Self.selectionContextMatches(originalValue: target.fieldValue, originalRange: target.selectedRange,
                                           currentValue: currentValue, currentRange: currentRange) else {
            status = "The original field or selection changed. Nothing was inserted."
            return false
        }
        return performInsertion(text, app: app, element: focused,
                                originalValue: currentValue, selectedRange: currentRange)
    }

    /// Where a captured target stands right now. Never activates or focuses anything.
    func focusState(of target: InsertionTarget) -> (appIsFrontmost: Bool, fieldIsFocused: Bool) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return (false, false)
        }
        guard let focused = focusedElement(expectedProcessIdentifier: target.processIdentifier) else { return (true, false) }
        return (true, CFEqual(target.element, focused))
    }

    func focusState(of target: PasteTarget) -> (appIsFrontmost: Bool, fieldIsFocused: Bool) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return (false, false)
        }
        guard let focused = focusedElement(expectedProcessIdentifier: target.processIdentifier) else { return (true, false) }
        return (true, CFEqual(target.element, focused))
    }

    /// Types at the current cursor of a captured field, but only while that exact field still
    /// has keyboard focus. Unlike `insert(_:into:)` it never switches apps, so text cannot land
    /// somewhere the user has since moved away from.
    @discardableResult
    func insert(_ text: String, ifStillFocused target: InsertionTarget) -> Bool {
        requiresReviewAfterInsertion = false
        lastDeliveryVerified = true
        guard isEnabled, AXIsProcessTrusted() else {
            isEnabled = false
            status = "Accessibility access is unavailable. Text was not inserted."
            return false
        }
        guard !text.isEmpty,
              let app = NSRunningApplication(processIdentifier: target.processIdentifier),
              !app.isTerminated,
              app.bundleIdentifier == target.bundleIdentifier else {
            status = "The original app is no longer available. Nothing was inserted."
            return false
        }
        let state = focusState(of: target)
        guard state.appIsFrontmost, state.fieldIsFocused,
              let focused = focusedElement(expectedProcessIdentifier: target.processIdentifier) else {
            status = "\(target.applicationName) or its text field is no longer focused. Nothing was inserted."
            return false
        }
        return performInsertion(text, app: app, element: focused,
                                originalValue: stringAttribute(kAXValueAttribute, of: focused),
                                selectedRange: selectedTextRange(of: focused))
    }

    /// Captures a readable, non-password text field before dictation starts. The snapshot lets
    /// paste validate that neither focus nor field contents changed while the user was speaking.
    func capturePasteTarget(into app: NSRunningApplication) -> PasteTarget? {
        guard isEnabled, allowsPasteFallback, AXIsProcessTrusted(), !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        exposeWebContent(of: app)
        guard let focused = focusedElement(expectedProcessIdentifier: app.processIdentifier),
              !isPasswordElement(focused) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success, pid == app.processIdentifier else { return nil }
        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, of: focused) ?? ""
        guard Self.isSupportedPasteTarget(role: role, subrole: subrole),
              let fieldValue = stringAttribute(kAXValueAttribute, of: focused),
              fieldValue.utf16.count <= 20_000,
              let selectedRange = selectedTextRange(of: focused),
              selectedRange.location <= fieldValue.utf16.count,
              selectedRange.length <= fieldValue.utf16.count - selectedRange.location else { return nil }
        return PasteTarget(processIdentifier: app.processIdentifier,
                           bundleIdentifier: app.bundleIdentifier,
                           applicationName: app.localizedName ?? "The app",
                           element: focused, role: role, subrole: subrole,
                           fieldValue: fieldValue, selectedRange: selectedRange)
    }

    /// Pastes with ⌘V into the frontmost app when its field can't be read back to verify the paste
    /// (Monaco, Electron and other contenteditable editors). Only sent when that app has a focused,
    /// editable, non-password element: with nothing to type into, the words would vanish, so the
    /// caller shows the Copy card instead.
    @discardableResult
    func pasteDirectly(_ text: String, into app: NSRunningApplication) async -> Bool {
        guard isEnabled, allowsPasteFallback, AXIsProcessTrusted(), !app.isTerminated, !text.isEmpty,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              app.bundleIdentifier != "com.ruddvz.hushkey" else { return false }
        exposeWebContent(of: app)
        let name = app.localizedName ?? "the app"
        guard let focused = focusedElement(expectedProcessIdentifier: app.processIdentifier) else {
            status = "Nothing has focus in \(name). Nothing was pasted."
            return false
        }
        var pid: pid_t = 0
        var settable = DarwinBoolean(false)
        let selectedTextSettable = AXUIElementIsAttributeSettable(
            focused, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        var ancestor: CFTypeRef?
        let hasEditableAncestor = AXUIElementCopyAttributeValue(
            focused, "AXEditableAncestor" as CFString, &ancestor) == .success && ancestor != nil
        guard AXUIElementGetPid(focused, &pid) == .success, pid == app.processIdentifier,
              !isPasswordElement(focused),
              Self.allowsUnverifiedPaste(role: stringAttribute(kAXRoleAttribute, of: focused) ?? "",
                                         subrole: stringAttribute(kAXSubroleAttribute, of: focused) ?? "",
                                         selectedTextSettable: selectedTextSettable,
                                         hasEditableAncestor: hasEditableAncestor) else {
            status = "No text box is focused in \(name). Nothing was pasted."
            return false
        }

        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard)
        let ours = ClipboardSnapshot.placeTransient(text, on: pasteboard)
        guard Self.postCommandV() else {
            _ = saved.restore(to: pasteboard, ifChangeCountIs: ours)
            status = "The paste shortcut could not be sent to \(name). Nothing was inserted."
            return false
        }
        // Electron and web editors read the pasteboard asynchronously; putting the old clipboard
        // back too soon pastes that instead of the dictation.
        try? await Task.sleep(for: Self.unverifiedPasteRestoreDelay)
        let restored = saved.restore(to: pasteboard, ifChangeCountIs: ours)
        let clipboard = restored ? "Your clipboard was put back." : "The clipboard changed meanwhile, so it was left as is."
        status = "Pasted into \(name). \(clipboard)"
        lastDeliveryVerified = false
        return true
    }

    nonisolated static let unverifiedPasteRestoreDelay: Duration = .milliseconds(500)

    /// Whether an element that can't be read back still looks like somewhere to type: a text role,
    /// a settable selection, or (Chromium) an editable ancestor. Never a password field.
    nonisolated static func allowsUnverifiedPaste(role: String, subrole: String,
                                                  selectedTextSettable: Bool, hasEditableAncestor: Bool) -> Bool {
        guard subrole != (kAXSecureTextFieldSubrole as String),
              !role.localizedCaseInsensitiveContains("secure"),
              !subrole.localizedCaseInsensitiveContains("secure"),
              !subrole.localizedCaseInsensitiveContains("password") else { return false }
        return isSupportedTextTarget(role: role, subrole: subrole) || selectedTextSettable || hasEditableAncestor
    }

    /// Whether a readable, non-password field is in front and eligible for verified paste.
    func canPaste(into app: NSRunningApplication) -> Bool {
        capturePasteTarget(into: app) != nil
    }

    /// Pastes only into the exact readable field captured before dictation. The operation is
    /// considered successful only after that field exposes the expected replacement text.
    func paste(_ text: String, into app: NSRunningApplication, target: PasteTarget) async -> PasteOutcome {
        let text = Self.spacedInsertion(text, fieldValue: target.fieldValue, selectedRange: target.selectedRange)
        let name = target.applicationName
        guard !text.isEmpty, isEnabled, allowsPasteFallback, AXIsProcessTrusted(),
              !app.isTerminated, app.processIdentifier == target.processIdentifier,
              app.bundleIdentifier == target.bundleIdentifier,
              let currentValue = validatedPasteTargetValue(target, in: app),
              currentValue == target.fieldValue,
              let expectedValue = Self.expectedPasteValue(originalValue: target.fieldValue,
                                                           selectedRange: target.selectedRange,
                                                           insertedText: text) else {
            status = "The original text field or selection changed. Nothing was pasted."
            return .unavailable
        }
        // Replacing a selection with identical text has no observable value change, so do not
        // send a paste that could not be distinguished from a missed paste.
        guard expectedValue != target.fieldValue else {
            status = "The selected text already matches this dictation. Nothing needed to change."
            return .inserted
        }
        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard)
        let ours = ClipboardSnapshot.placeTransient(text, on: pasteboard)
        guard Self.postCommandV() else {
            _ = saved.restore(to: pasteboard, ifChangeCountIs: ours)
            status = "The paste shortcut could not be sent to \(name). Nothing was inserted."
            return .unavailable
        }
        let verification = await PasteDeliveryVerifier.waitForConfirmation(
            originalValue: target.fieldValue, expectedValue: expectedValue) {
            self.pasteObservation(target: target, in: app)
        }
        if verification != .confirmed {
            try? await Task.sleep(for: .milliseconds(80))
        }
        let restored = saved.restore(to: pasteboard, ifChangeCountIs: ours)
        guard verification == .confirmed else {
            logPasteMismatch(verification, target: target, expectedValue: expectedValue, insertedText: text, in: app)
            undoRecord = nil
            let clipboard = restored ? "Your clipboard was put back." : "The clipboard changed meanwhile, so it was left as is."
            status = verification == .targetChanged
                ? "Paste was sent to \(name), but focus or field contents changed before confirmation. Check the field before retrying; a retry could duplicate text. \(clipboard)"
                : "Paste was sent to \(name), but HushKey could not verify the exact field contents. Check the field before retrying; a retry could duplicate text. \(clipboard)"
            lastDeliveryVerified = false
            return .unconfirmed
        }
        if let possibleUndo = Self.makeUndoRecord(processIdentifier: target.processIdentifier,
                                                  bundleIdentifier: target.bundleIdentifier,
                                                  element: target.element,
                                                  originalValue: target.fieldValue,
                                                  selectedRange: target.selectedRange,
                                                  insertedText: text) {
            undoRecord = possibleUndo
        } else {
            undoRecord = nil
        }
        let clipboard = restored ? "Your clipboard was put back." : "The clipboard changed meanwhile, so it was left as is."
        status = "Pasted into \(name) and verified in the same text field. \(clipboard)"
        lastDeliveryVerified = true
        return .inserted
    }

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let source,
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func validatedPasteTargetValue(_ target: PasteTarget, in app: NSRunningApplication) -> String? {
        guard !app.isTerminated, app.processIdentifier == target.processIdentifier,
              app.bundleIdentifier == target.bundleIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let current = focusedElement(expectedProcessIdentifier: target.processIdentifier),
              CFEqual(target.element, current) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(current, &pid) == .success, pid == target.processIdentifier,
              stringAttribute(kAXRoleAttribute, of: current) == target.role,
              (stringAttribute(kAXSubroleAttribute, of: current) ?? "") == target.subrole,
              Self.isSupportedPasteTarget(role: target.role, subrole: target.subrole),
              let currentValue = stringAttribute(kAXValueAttribute, of: current),
              let currentRange = selectedTextRange(of: current),
              currentRange.location <= currentValue.utf16.count,
              currentRange.length <= currentValue.utf16.count - currentRange.location else {
            return nil
        }
        if currentValue == target.fieldValue,
           !Self.selectionContextMatches(originalValue: target.fieldValue, originalRange: target.selectedRange,
                                         currentValue: currentValue, currentRange: currentRange) { return nil }
        return currentValue
    }

    private func pasteObservation(target: PasteTarget, in app: NSRunningApplication)
        -> PasteDeliveryVerifier.Observation {
        guard !app.isTerminated, app.processIdentifier == target.processIdentifier else { return .targetChanged }
        if let value = validatedPasteTargetValue(target, in: app) { return .fieldValue(value) }
        // Electron editors (Claude, Slack) can rebuild the focused element when a paste lands.
        // A replacement in the same app with the same role still counts as the field; its value
        // must then match the expected text before the paste is confirmed.
        guard let value = replacementFieldValue(target, in: app) else { return .targetChanged }
        return .fieldValue(value)
    }

    private func replacementFieldValue(_ target: PasteTarget, in app: NSRunningApplication) -> String? {
        var pid: pid_t = 0
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let current = focusedElement(expectedProcessIdentifier: target.processIdentifier),
              AXUIElementGetPid(current, &pid) == .success, pid == target.processIdentifier,
              stringAttribute(kAXRoleAttribute, of: current) == target.role else { return nil }
        return stringAttribute(kAXValueAttribute, of: current)
    }

    /// Says why a paste could not be confirmed, so a field that reports its text differently can be
    /// diagnosed. Logs only lengths and flags, never text.
    private func logPasteMismatch(_ result: PasteDeliveryVerifier.Result, target: PasteTarget,
                                  expectedValue: String, insertedText: String, in app: NSRunningApplication) {
        let sameElement = validatedPasteTargetValue(target, in: app) != nil
        let observed = validatedPasteTargetValue(target, in: app) ?? replacementFieldValue(target, in: app)
        var line = "paste unconfirmed result=\(result) app=\(target.bundleIdentifier ?? "none") sameElement=\(sameElement)"
        line += " original=\(target.fieldValue.utf16.count) expected=\(expectedValue.utf16.count)"
        if let observed {
            let inserted = PasteDeliveryVerifier.normalized(insertedText)
            line += " observed=\(observed.utf16.count)"
            line += " normalizedMatch=\(PasteDeliveryVerifier.matches(observed, expectedValue))"
            line += " containsInsertedOnce=\(observed.components(separatedBy: inserted).count == 2)"
            line += " containsInsertedTwice=\(observed.components(separatedBy: inserted).count > 2)"
            line += " nbsp=\(observed.filter { $0 == "\u{00A0}" }.count) newlines=\(observed.filter(\.isNewline).count)"
        } else {
            line += " observed=none"
        }
        log.notice("\(line, privacy: .public)")
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
        guard let current = focusedElement(expectedProcessIdentifier: record.processIdentifier),
              CFEqual(record.element, current),
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

    nonisolated static func isSupportedTextTarget(role: String, subrole: String) -> Bool {
        guard subrole != (kAXSecureTextFieldSubrole as String) else { return false }
        guard !role.localizedCaseInsensitiveContains("secure"),
              !subrole.localizedCaseInsensitiveContains("secure"),
              !subrole.localizedCaseInsensitiveContains("password") else { return false }
        return [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
    }

    nonisolated static func isSupportedPasteTarget(role: String, subrole: String) -> Bool {
        isSupportedTextTarget(role: role, subrole: subrole)
    }

    nonisolated static func expectedPasteValue(originalValue: String, selectedRange: CFRange,
                                               insertedText: String) -> String? {
        let field = originalValue as NSString
        guard selectedRange.location >= 0, selectedRange.length >= 0,
              selectedRange.location <= field.length,
              selectedRange.length <= field.length - selectedRange.location else { return nil }
        return field.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: insertedText)
    }

    nonisolated static func directInsertionVerification(originalValue: String,
                                                        expectedValue: String,
                                                        observedValue: String) -> DirectInsertionVerification {
        if observedValue == expectedValue { return .verified }
        if observedValue == originalValue { return .unchanged }
        return .changedUnexpectedly
    }

    nonisolated static func selectionContextMatches(originalValue: String, originalRange: CFRange,
                                                   currentValue: String, currentRange: CFRange) -> Bool {
        originalValue == currentValue &&
            originalRange.location == currentRange.location &&
            originalRange.length == currentRange.length
    }

    nonisolated static func selectedText(in fieldValue: String, range: CFRange,
                                         maximumCharacters: Int = 12_000) -> String? {
        let field = fieldValue as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= field.length,
              range.length <= field.length - range.location,
              range.length <= maximumCharacters else { return nil }
        return field.substring(with: NSRange(location: range.location, length: range.length))
    }

    /// The fixed undo shortcut, ⌥⇧U.
    static let undoShortcut = KeyCombo(.key(UInt32(kVK_ANSI_U)), modifiers: [.option, .shift])

    /// Settings is recording a shortcut; free the keys until it's done.
    func suspendShortcuts() {
        hotKey.unregister()
        undoHotKey.unregister()
    }

    func resumeShortcuts() {
        guard isEnabled else { return }
        registerShortcut()
        _ = undoHotKey.register(keyCode: Self.undoShortcut.keyCode,
                                modifiers: Self.undoShortcut.carbonModifiers) { [weak self] in
            self?.onUndoShortcut?()
        }
    }

    private func registerShortcut() {
        let result = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.onInsertShortcut?()
        }
        status = result == noErr
            ? "Enabled. Insert with \(shortcut.label); undo immediately with ⌥⇧U while the same field stays focused."
            : "Could not register \(shortcut.label) (system status \(result))."
    }

    /// Electron apps (Claude, Slack, VS Code, Notion…) hide their text boxes from accessibility
    /// until a client asks for them, so HushKey would see no focused field there. Ask as each app
    /// comes to the front, so the field is ready by the time dictation starts.
    private func watchActivations() {
        guard activationObserver == nil else { return }
        if let app = NSWorkspace.shared.frontmostApplication { exposeWebContent(of: app) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.exposeWebContent(of: app) }
        }
    }

    private func exposeWebContent(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isEnabled, pid != NSRunningApplication.current.processIdentifier,
              !exposedProcesses.contains(pid) else { return }
        exposedProcesses.insert(pid)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    @ObservationIgnored private let log = Logger(subsystem: "com.ruddvz.hushkey", category: "insertion")

    /// Records what HushKey sees in the focused app, so a field it cannot type into can be
    /// diagnosed with `log show --predicate 'subsystem == "com.ruddvz.hushkey"'`. Never logs text.
    func logFocus(_ moment: String) {
        let app = NSWorkspace.shared.frontmostApplication
        var line = "\(moment): enabled=\(isEnabled) trusted=\(AXIsProcessTrusted()) app=\(app?.bundleIdentifier ?? "none")"
        if let focused = focusedElement(expectedProcessIdentifier: app?.processIdentifier) {
            var settable = DarwinBoolean(false)
            let settableResult = AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable)
            line += " role=\(stringAttribute(kAXRoleAttribute, of: focused) ?? "nil")"
            line += " subrole=\(stringAttribute(kAXSubroleAttribute, of: focused) ?? "nil")"
            line += " hasValue=\(stringAttribute(kAXValueAttribute, of: focused) != nil)"
            line += " hasRange=\(selectedTextRange(of: focused) != nil)"
            line += " selectedTextSettable=\(settableResult.rawValue):\(settable.boolValue)"
        } else {
            line += " focused=none"
        }
        log.notice("\(line, privacy: .public) status=\(self.status, privacy: .public)")
    }

    /// Web password fields can report a plain text role with AXIsPassword set.
    private func isPasswordElement(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXIsPassword" as CFString, &value) == .success
            && (value as? Bool) == true
    }

    private func focusedElement(expectedProcessIdentifier: pid_t? = nil) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        let focusedApplication = accessibilityElement(kAXFocusedApplicationAttribute, of: systemWide)
        let applicationFocus = focusedApplication.flatMap {
            accessibilityElement(kAXFocusedUIElementAttribute, of: $0)
        }
        let systemWideFocus = accessibilityElement(kAXFocusedUIElementAttribute, of: systemWide)
        let frontmostFocus: AXUIElement?
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            frontmostFocus = accessibilityElement(kAXFocusedUIElementAttribute, of: appElement)
        } else {
            frontmostFocus = nil
        }
        return Self.preferredFocusedElement(applicationFocusedElement: applicationFocus,
                                            systemWideFocusedElement: systemWideFocus,
                                            frontmostApplicationFocusedElement: frontmostFocus,
                                            expectedProcessIdentifier: expectedProcessIdentifier,
                                            processIdentifier: Self.processIdentifier(of:))
    }

    private func accessibilityElement(_ attribute: String, of parent: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated static func preferredFocusedElement<Element>(applicationFocusedElement: Element?,
                                                             systemWideFocusedElement: Element?,
                                                             frontmostApplicationFocusedElement: Element?,
                                                             expectedProcessIdentifier: pid_t?,
                                                             processIdentifier: (Element) -> pid_t?) -> Element? {
        for candidate in [applicationFocusedElement, systemWideFocusedElement,
                          frontmostApplicationFocusedElement].compactMap({ $0 }) {
            guard let expectedProcessIdentifier else { return candidate }
            if processIdentifier(candidate) == expectedProcessIdentifier { return candidate }
        }
        return nil
    }

    nonisolated private static func processIdentifier(of element: AXUIElement) -> pid_t? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else { return nil }
        return processIdentifier
    }

    private func performInsertion(_ text: String, app: NSRunningApplication, element: AXUIElement,
                                  originalValue: String?, selectedRange: CFRange?) -> Bool {
        requiresReviewAfterInsertion = false
        lastDeliveryVerified = true
        var focusedPID: pid_t = 0
        var settable = DarwinBoolean(false)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let currentElement = focusedElement(expectedProcessIdentifier: app.processIdentifier),
              CFEqual(element, currentElement),
              AXUIElementGetPid(currentElement, &focusedPID) == .success,
              focusedPID == app.processIdentifier,
              Self.isSupportedTextTarget(role: stringAttribute(kAXRoleAttribute, of: currentElement) ?? "",
                                         subrole: stringAttribute(kAXSubroleAttribute, of: currentElement) ?? ""),
              AXUIElementIsAttributeSettable(currentElement, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let originalValue,
              let currentValue = stringAttribute(kAXValueAttribute, of: currentElement),
              let selectedRange,
              let currentRange = selectedTextRange(of: currentElement),
              Self.selectionContextMatches(originalValue: originalValue, originalRange: selectedRange,
                                           currentValue: currentValue, currentRange: currentRange) else {
            status = "Focus or text changed before insertion. Nothing was inserted."
            return false
        }
        let text = Self.spacedInsertion(text, fieldValue: currentValue, selectedRange: currentRange)
        guard let expectedValue = Self.expectedPasteValue(originalValue: currentValue,
                                                          selectedRange: currentRange,
                                                          insertedText: text) else {
            status = "The target text could not be checked. Nothing was inserted."
            return false
        }
        if expectedValue == currentValue {
            undoRecord = nil
            status = "The selected text already matches. Nothing needed to change."
            return true
        }
        let possibleUndo = Self.makeUndoRecord(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            element: currentElement,
            originalValue: currentValue,
            selectedRange: currentRange,
            insertedText: text)
        guard AXUIElementSetAttributeValue(currentElement, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            status = "The focused app declined safe insertion. Nothing was inserted."
            return false
        }
        guard let observedValue = stringAttribute(kAXValueAttribute, of: currentElement) else {
            undoRecord = nil
            requiresReviewAfterInsertion = true
            lastDeliveryVerified = false
            status = "HushKey sent the text, but could not read it back to confirm. Check the field before retrying to avoid a duplicate."
            return false
        }
        switch Self.directInsertionVerification(originalValue: currentValue,
                                                expectedValue: expectedValue,
                                                observedValue: observedValue) {
        case .verified:
            if let possibleUndo, Self.fingerprint(observedValue) == possibleUndo.expectedFingerprint {
                undoRecord = possibleUndo
                status = "Inserted and verified in the focused field. Press ⌥⇧U now to undo while it stays focused and unchanged."
            } else {
                undoRecord = nil
                status = "Inserted and verified in the focused field. A safe undo record is unavailable."
            }
            return true
        case .unchanged:
            undoRecord = nil
            status = "The focused field did not change. Nothing was inserted."
            return false
        case .changedUnexpectedly:
            undoRecord = nil
            requiresReviewAfterInsertion = true
            lastDeliveryVerified = false
            status = "The focused field changed, but HushKey could not confirm the exact text. Check it before retrying to avoid a duplicate."
            return false
        }
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Dictation placed right after a word or sentence gets a separating space, as if typed.
    nonisolated static func spacedInsertion(_ text: String, fieldValue: String?, selectedRange: CFRange?) -> String {
        guard let fieldValue, let selectedRange, selectedRange.location > 0 else { return text }
        let value = fieldValue as NSString
        guard selectedRange.location <= value.length else { return text }
        let before = value.substring(with: value.rangeOfComposedCharacterSequence(at: selectedRange.location - 1))
        return spaced(text, after: before.last)
    }

    nonisolated static func spaced(_ text: String, after preceding: Character?) -> String {
        guard let preceding, let first = text.first,
              !preceding.isWhitespace, !first.isWhitespace,
              !"([{“‘/-–—@#\"'".contains(preceding),
              !".,;:!?)]}…%’”".contains(first) else { return text }
        return " " + text
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

@MainActor
enum PasteDeliveryVerifier {
    enum Observation: Equatable {
        case fieldValue(String)
        case targetChanged
    }

    enum Result: Equatable {
        case confirmed
        case timedOut
        case targetChanged
    }

    static func waitForConfirmation(originalValue: String,
                                    expectedValue: String,
                                    maximumChecks: Int = 20,
                                    interval: Duration = .milliseconds(25),
                                    observe: () -> Observation) async -> Result {
        guard maximumChecks > 0 else { return .timedOut }
        for check in 0..<maximumChecks {
            switch observe() {
            case .fieldValue(let value) where matches(value, expectedValue):
                return .confirmed
            case .fieldValue(let value) where matches(value, originalValue):
                break
            case .fieldValue:
                return .targetChanged
            case .targetChanged:
                return .targetChanged
            }
            guard check + 1 < maximumChecks else { continue }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return .timedOut
            }
        }
        return .timedOut
    }

    /// Whether a field shows the same text, as a reader would see it. Chromium editors report a
    /// typed space as a non-breaking space, add a newline for an empty paragraph, and may carry
    /// zero-width characters, none of which the pasted text contains.
    static func matches(_ observed: String, _ expected: String) -> Bool {
        observed == expected || normalized(observed) == normalized(expected)
    }

    static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
