import Carbon

/// Carbon registers one shortcut without monitoring all keyboard input or requiring Accessibility.
final class GlobalShortcut {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Use the dispatcher target so the registration is independent of the active AppKit window.
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x464F4C44, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        guard enabled else { return true }
        guard handler != nil else { return false }
        let identifier = EventHotKeyID(signature: 0x464F4C44, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey), identifier,
                                   GetEventDispatcherTarget(), 0, &reference) == noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
