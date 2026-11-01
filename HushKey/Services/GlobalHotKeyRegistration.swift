import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyRegistration {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> OSStatus {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let signature = OSType(0x48555348) // HUSH
        let installStatus = InstallEventHandler(
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
                guard readStatus == noErr, received.signature == OSType(0x48555348), received.id == 1 else { return noErr }
                let owner = Unmanaged<GlobalHotKeyRegistration>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in owner.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
        guard installStatus == noErr else { return installStatus }

        let identifier = EventHotKeyID(signature: signature, id: 1)
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
