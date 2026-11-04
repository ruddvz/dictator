import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What the recorder makes of each event while it listens. Pure, so the rules are unit tested:
/// a key with modifiers is recorded on key down, fn on its own is recorded when it's released
/// with nothing pressed in between, Escape on its own cancels.
struct ShortcutCapture {
    enum Outcome: Equatable { case listening, cancelled, captured(KeyCombo) }

    private var functionKeyDown = false
    private var keyPressedWithFunction = false

    mutating func keyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Outcome {
        let modifiers = KeyCombo.Modifiers(modifierFlags)
        if keyCode == UInt16(kVK_Escape), modifiers.isEmpty { return .cancelled }
        if functionKeyDown { keyPressedWithFunction = true }
        guard let combo = KeyCombo(keyCode: keyCode, modifierFlags: modifierFlags) else { return .listening }
        return .captured(combo)
    }

    mutating func flagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Outcome {
        guard keyCode == UInt16(kVK_Function) else {
            // Another modifier joined fn: this is a chord, not fn on its own.
            if functionKeyDown { keyPressedWithFunction = true }
            return .listening
        }
        if modifierFlags.contains(.function) {
            functionKeyDown = true
            keyPressedWithFunction = !KeyCombo.Modifiers(modifierFlags).isEmpty
            return .listening
        }
        defer { functionKeyDown = false; keyPressedWithFunction = false }
        return functionKeyDown && !keyPressedWithFunction ? .captured(.functionKey) : .listening
    }

    mutating func mouseDown(button: Int) -> Outcome {
        KeyCombo(mouseButton: button).map(Outcome.captured) ?? .listening
    }
}

/// Owns the one live key monitor, so starting a second recorder ends the first.
@MainActor
private final class ShortcutRecorderSession {
    static let shared = ShortcutRecorderSession()

    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var capture = ShortcutCapture()
    private var finish: ((ShortcutCapture.Outcome) -> Void)?

    func begin(onFinish: @escaping (ShortcutCapture.Outcome) -> Void) {
        end(with: .cancelled)
        capture = ShortcutCapture()
        finish = onFinish
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                let outcome: ShortcutCapture.Outcome
                switch event.type {
                case .keyDown: outcome = self.capture.keyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
                case .flagsChanged: outcome = self.capture.flagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
                case .otherMouseDown: outcome = self.capture.mouseDown(button: event.buttonNumber)
                default: outcome = .listening
                }
                if outcome != .listening { self.end(with: outcome) }
                // Swallow keys so ⌘Q or ⌘W are recorded instead of quitting or closing.
                return event.type == .flagsChanged ? event : nil
            }
        }
        // Switching apps mid-recording would leave every HushKey shortcut off.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.end(with: .cancelled) }
        }
    }

    func end(with outcome: ShortcutCapture.Outcome) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        let finish = finish
        self.finish = nil
        finish?(outcome)
    }
}

/// Click, then press the keys (or a side mouse button) to set a shortcut. Checks the result
/// against HushKey's other shortcuts and the standard macOS ones before saving it.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    let action: ShortcutAction
    let combo: KeyCombo?
    let defaultCombo: KeyCombo
    var resetLabel = "Reset"
    var allowsTurningOff = false
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var problem: ShortcutProblem?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: Theme.s2) {
                Button(action: toggleRecording) {
                    Group {
                        if isRecording {
                            Text(prompt)
                                .font(.hkControl)
                                .foregroundStyle(Theme.signal)
                        } else if let combo {
                            KeycapShortcut(label: combo.label, size: 12)
                        } else {
                            Text("Off")
                                .font(.hkControl)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .padding(.horizontal, Theme.s3)
                    .frame(minWidth: 120, minHeight: Theme.controlHeight)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(isRecording ? Theme.signal : Theme.hairline, lineWidth: isRecording ? 1.5 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Press the new shortcut, or Escape to cancel." : "Click, then press the new shortcut.")
                .accessibilityLabel(isRecording ? "Recording \(action.title) shortcut"
                                    : "\(action.title) shortcut, \(combo?.label ?? "off"). Click to change.")

                if isRecording {
                    Button("Cancel") { ShortcutRecorderSession.shared.end(with: .cancelled) }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    if combo != defaultCombo {
                        Button(resetLabel) { apply(defaultCombo) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if allowsTurningOff, combo != nil {
                        Button("Turn off") { problem = nil; onChange(nil) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            if let problem {
                Text(problem.message)
                    .font(.hkCaption)
                    .foregroundStyle(problem.blocksSaving ? Theme.danger : Theme.ink2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Theme.snappy, value: isRecording)
        .animation(Theme.snappy, value: problem)
        .onDisappear { if isRecording { ShortcutRecorderSession.shared.end(with: .cancelled) } }
    }

    private var prompt: String {
        if action.allowsFunctionKey { return "Press keys or fn…" }
        return action.allowsMouseButton ? "Press keys or a button…" : "Press keys…"
    }

    private func toggleRecording() {
        if isRecording {
            ShortcutRecorderSession.shared.end(with: .cancelled)
            return
        }
        problem = nil
        isRecording = true
        // Begin first: it ends any other recorder, which turns shortcuts back on as it goes.
        ShortcutRecorderSession.shared.begin { outcome in
            isRecording = false
            model.resumeShortcuts()
            if case .captured(let recorded) = outcome { apply(recorded) }
        }
        model.suspendShortcuts()
    }

    private func apply(_ recorded: KeyCombo) {
        problem = ShortcutConflicts.problem(with: recorded, for: action, assignments: model.shortcutAssignments)
        if problem?.blocksSaving == true { return }
        if recorded != combo { onChange(recorded) }
    }
}
