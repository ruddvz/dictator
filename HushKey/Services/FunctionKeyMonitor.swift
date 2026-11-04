import AppKit
import Carbon.HIToolbox
import os

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

    /// fn taps toggle hands-free dictation. Silent capture has no hands-free mode, so a quick
    /// Control hold simply ends the capture and the take is judged on its own length.
    var supportsHandsFree = true
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
        guard supportsHandsFree else { return wasHolding ? .endHold : .cancelHoldStart }
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

/// Watches a lone modifier key system-wide: fn for dictation, Control for Silent Use.
/// Global key monitoring needs Accessibility access, which HushKey already asks for to insert text.
@MainActor
final class FunctionKeyMonitor {
    enum Key {
        case function
        case control

        var keyCodes: Set<UInt16> {
            switch self {
            case .function: [UInt16(kVK_Function)]
            case .control: [UInt16(kVK_Control), UInt16(kVK_RightControl)]
            }
        }

        var flag: NSEvent.ModifierFlags {
            switch self {
            case .function: .function
            case .control: .control
            }
        }

        /// The same key in the keyboard's live hardware state.
        var hardwareFlag: CGEventFlags {
            switch self {
            case .function: .maskSecondaryFn
            case .control: .maskControl
            }
        }

        /// Modifiers that turn a press into a shortcut. fn is excluded for fn itself because macOS
        /// sets it on arrow and F-key events too.
        var otherModifiers: NSEvent.ModifierFlags {
            switch self {
            case .function: [.command, .option, .control, .shift]
            case .control: [.command, .option, .shift, .function]
            }
        }

        var supportsHandsFree: Bool { self == .function }

        /// Control is held for clicks too (⌃-click opens a context menu), so a click cancels its hold.
        var watchedEvents: NSEvent.EventTypeMask {
            switch self {
            case .function: [.flagsChanged, .keyDown]
            case .control: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            }
        }
    }

    let key: Key
    var onAction: ((FunctionKeyGesture.Action) -> Void)?
    private(set) var gesture = FunctionKeyGesture()
    private var monitors: [Any] = []
    private var holdTimer: DispatchWorkItem?
    /// A release that arrived while the keyboard still reports the key down, waiting to be
    /// confirmed by the hardware state or by the next press.
    private var pendingRelease: DispatchWorkItem?
    private let log = Logger(subsystem: "com.ruddvz.hushkey", category: "shortcut")

    /// How often an unconfirmed release re-checks the keyboard.
    static let releaseRecheck: TimeInterval = 0.05

    var isInstalled: Bool { !monitors.isEmpty }

    init(key: Key = .function) {
        self.key = key
        gesture.supportsHandsFree = key.supportsHandsFree
    }

    func install() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: key.watchedEvents, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: key.watchedEvents, handler: { event in
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
        pendingRelease?.cancel()
        pendingRelease = nil
        gesture = FunctionKeyGesture()
        gesture.supportsHandsFree = key.supportsHandsFree
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
        case .flagsChanged where key.keyCodes.contains(event.keyCode):
            let others = event.modifierFlags.intersection(key.otherModifiers)
            if event.modifierFlags.contains(key.flag), others.isEmpty {
                // A press proves any pending release was real: end that hold first.
                flushPendingRelease(at: now)
                action = gesture.fnDown(at: now)
            } else if !event.modifierFlags.contains(key.flag) {
                guard !keyIsPhysicallyDown else {
                    // Some events report the key up while it is still held, which used to end
                    // a dictation mid-sentence. Wait for the keyboard to agree.
                    log.info("\(String(describing: self.key)) release ignored: key still held")
                    awaitPhysicalRelease()
                    return
                }
                action = gesture.fnUp(at: now)
            } else {
                action = gesture.otherKeyDown()
            }
        case .flagsChanged where gesture.isDown:
            action = gesture.otherKeyDown() // another modifier joined fn
        case .keyDown where gesture.isDown:
            action = gesture.otherKeyDown()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard gesture.isDown else { return }
            action = gesture.otherKeyDown() // ⌃-click is a right-click, not a silent word
        default:
            return
        }
        perform(action)
    }

    private var keyIsPhysicallyDown: Bool {
        CGEventSource.flagsState(.hidSystemState).contains(key.hardwareFlag)
    }

    private func awaitPhysicalRelease() {
        guard pendingRelease == nil, gesture.isDown else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingRelease != nil else { return }
            self.pendingRelease = nil
            if self.keyIsPhysicallyDown { self.awaitPhysicalRelease() }
            else { self.flushRelease(at: ProcessInfo.processInfo.systemUptime) }
        }
        pendingRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseRecheck, execute: work)
    }

    private func flushPendingRelease(at time: TimeInterval) {
        guard pendingRelease != nil else { return }
        flushRelease(at: time)
    }

    private func flushRelease(at time: TimeInterval) {
        pendingRelease?.cancel()
        pendingRelease = nil
        perform(gesture.fnUp(at: time))
    }

    private func perform(_ action: FunctionKeyGesture.Action) {
        if action != .none, action != .scheduleHoldStart {
            log.info("\(String(describing: self.key)) \(String(describing: action))")
        }
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
