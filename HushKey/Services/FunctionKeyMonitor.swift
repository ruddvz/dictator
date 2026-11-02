import AppKit
import Carbon.HIToolbox

/// Turns presses of the fn (Globe) key into dictation gestures:
/// hold to talk, double-tap to dictate hands-free, tap again to stop.
/// Pure state machine so the timing rules can be unit tested without a keyboard.
struct FunctionKeyGesture {
    enum Action: Equatable { case none, scheduleHoldStart, cancelHoldStart, startHold, endHold, abortHold, startHandsFree, stopHandsFree }

    /// fn must stay down this long before dictation starts, so fn+arrow and fn+F-key combos never trigger it.
    static let holdDelay: TimeInterval = 0.12
    /// A press shorter than this counts as a tap.
    static let tapLimit: TimeInterval = 0.3
    /// Two taps closer together than this start hands-free dictation.
    static let doubleTapWindow: TimeInterval = 0.4

    private(set) var isDown = false
    private(set) var isHolding = false
    private(set) var isHandsFree = false
    private var downAt: TimeInterval = 0
    private var lastTapAt: TimeInterval?
    private var interrupted = false

    mutating func fnDown(at time: TimeInterval) -> Action {
        guard !isDown else { return .none }
        isDown = true
        downAt = time
        interrupted = false
        if isHandsFree {
            isHandsFree = false
            interrupted = true // this press only stops; its release is not a tap
            lastTapAt = nil
            return .stopHandsFree
        }
        return .scheduleHoldStart
    }

    /// The hold delay elapsed with fn still down and nothing else pressed.
    mutating func holdDelayElapsed() -> Action {
        guard isDown, !interrupted, !isHolding else { return .none }
        isHolding = true
        return .startHold
    }

    /// Another key went down while fn was held: this is a shortcut, not dictation.
    mutating func otherKeyDown() -> Action {
        guard isDown, !interrupted else { return .none }
        interrupted = true
        lastTapAt = nil
        if isHolding {
            isHolding = false
            return .abortHold
        }
        return .cancelHoldStart
    }

    mutating func fnUp(at time: TimeInterval) -> Action {
        guard isDown else { return .none }
        isDown = false
        let wasHolding = isHolding
        isHolding = false
        if interrupted { return wasHolding ? .endHold : .none }
        let isTap = time - downAt < Self.tapLimit
        if isTap {
            if let last = lastTapAt, downAt - last < Self.doubleTapWindow {
                lastTapAt = nil
                isHandsFree = true
                return .startHandsFree
            }
            lastTapAt = time
            return wasHolding ? .abortHold : .cancelHoldStart
        }
        lastTapAt = nil
        return wasHolding ? .endHold : .cancelHoldStart
    }

    /// Dictation ended some other way (pill, Stop button), so forget hands-free.
    mutating func reset() {
        isHolding = false
        isHandsFree = false
        lastTapAt = nil
        interrupted = isDown
    }

    mutating func modalPanelDidOpen() -> Action {
        let action: Action = isHandsFree ? .stopHandsFree : isHolding ? .endHold : .none
        reset()
        return action
    }
}

/// Watches the fn key system-wide. Global key monitoring needs Accessibility access,
/// which HushKey already asks for to insert text.
@MainActor
final class FunctionKeyMonitor {
    var onAction: ((FunctionKeyGesture.Action) -> Void)?
    private(set) var gesture = FunctionKeyGesture()
    private var monitors: [Any] = []
    private var holdTimer: DispatchWorkItem?

    var isInstalled: Bool { !monitors.isEmpty }

    func install() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func uninstall() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        holdTimer?.cancel()
        gesture = FunctionKeyGesture()
    }

    func reset() { gesture.reset() }

    private func handle(_ event: NSEvent) {
        guard NSApp.modalWindow == nil else {
            holdTimer?.cancel()
            let action = gesture.modalPanelDidOpen()
            if action != .none { onAction?(action) }
            return
        }
        let now = event.timestamp
        let action: FunctionKeyGesture.Action
        switch event.type {
        case .flagsChanged where event.keyCode == UInt16(kVK_Function):
            let others = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.modifierFlags.contains(.function), others.isEmpty {
                action = gesture.fnDown(at: now)
            } else if !event.modifierFlags.contains(.function) {
                action = gesture.fnUp(at: now)
            } else {
                action = gesture.otherKeyDown()
            }
        case .flagsChanged where gesture.isDown:
            action = gesture.otherKeyDown() // another modifier joined fn
        case .keyDown where gesture.isDown:
            action = gesture.otherKeyDown()
        default:
            return
        }
        perform(action)
    }

    private func perform(_ action: FunctionKeyGesture.Action) {
        switch action {
        case .scheduleHoldStart:
            holdTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.perform(self.gesture.holdDelayElapsed())
            }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + FunctionKeyGesture.holdDelay, execute: work)
        case .cancelHoldStart, .endHold, .abortHold, .startHandsFree, .stopHandsFree:
            holdTimer?.cancel()
            if action != .cancelHoldStart { onAction?(action) }
        case .startHold:
            onAction?(action)
        case .none:
            break
        }
    }
}
