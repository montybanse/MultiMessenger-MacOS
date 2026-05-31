import AppKit
import Carbon.HIToolbox

/// Systemweiter Hotkey (Standard: Cmd+Shift+M) zum Hervorholen der App.
/// Nutzt Carbon RegisterEventHotKey – benötigt keine Bedienungshilfen-Freigabe.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    private init() {}

    func register() {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                HotKeyManager.shared.onTrigger?()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4D5347 /* 'MMSG' */), id: 1)
        // Cmd+Shift+M
        let keyCode = UInt32(kVK_ANSI_M)
        let modifiers = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let handler = eventHandler { RemoveEventHandler(handler); eventHandler = nil }
    }
}
