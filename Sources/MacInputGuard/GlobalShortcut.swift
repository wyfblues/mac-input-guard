import Carbon
import Foundation

final class GlobalProtectionShortcut {
    static let displayName = "⌃⌥⌘L"
    private static let signature: OSType = 0x4D494744 // MIGD
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    var isRegistered: Bool { hotKey != nil }

    @discardableResult
    func start(action: @escaping () -> Void) -> OSStatus {
        stop()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == GlobalProtectionShortcut.signature,
                  identity.id == 1 else { return OSStatus(eventNotHandledErr) }
            let instance = Unmanaged<GlobalProtectionShortcut>.fromOpaque(context).takeUnretainedValue()
            instance.action?()
            return noErr
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { stop(); return installed }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_L),
            UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registered == noErr else { stop(); return registered }
        return noErr
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
    deinit { stop() }
}
