import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyRegistration {
    private let identifier: UInt32
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: ((Bool) -> Void)?

    init(id: UInt32 = 1) { identifier = id }

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> OSStatus {
        register(keyCode: keyCode, modifiers: modifiers, includesRelease: false) { isPressed in
            if isPressed { action() }
        }
    }

    func registerHold(keyCode: UInt32, modifiers: UInt32, action: @escaping (Bool) -> Void) -> OSStatus {
        register(keyCode: keyCode, modifiers: modifiers, includesRelease: true, action: action)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, includesRelease: Bool,
                          action: @escaping (Bool) -> Void) -> OSStatus {
        unregister()
        self.action = action
        var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        if includesRelease {
            eventTypes.append(EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)))
        }
        let signature = OSType(0x48555348) // HUSH
        let installStatus = eventTypes.withUnsafeBufferPointer { types in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                guard let event, let userData else { return noErr }
                var received = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &received)
                guard readStatus == noErr, received.signature == OSType(0x48555348) else { return noErr }
                let owner = Unmanaged<GlobalHotKeyRegistration>.fromOpaque(userData).takeUnretainedValue()
                guard received.id == owner.identifier else { return noErr }
                let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                Task { @MainActor in owner.action?(isPressed) }
                return noErr
                },
                types.count,
                types.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler)
        }
        guard installStatus == noErr else { return installStatus }

        let identifier = EventHotKeyID(signature: signature, id: self.identifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey)
        if registerStatus != noErr {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            self.action = nil
        }
        return registerStatus
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }
}
