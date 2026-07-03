import Carbon.HIToolbox
import AppKit

/// Registers global hotkeys via the Carbon hotkey API (no accessibility permission needed).
final class HotkeyManager {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handlers[hkID.id]?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    /// keyCode is a kVK_* virtual key code; modifiers are Carbon masks (controlKey, shiftKey, ...).
    func register(keyCode: Int, modifiers: Int, handler: @escaping Handler) {
        let id = EventHotKeyID(signature: OSType(0x534E_4150) /* 'SNAP' */, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return }
        handlers[nextID] = handler
        refs.append(ref)
        nextID += 1
    }
}
