// ⌃⌥C from any app (docs/architecture/input-and-safety.md#escape-hatches-re-stated-because-theyre-non-negotiable).
// Carbon's RegisterEventHotKey: a registered hot key, not an event tap, so no Accessibility or
// Input Monitoring permission (non-negotiable #9). Unregistered on quit.
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// ⌃⌥C by default.
    init?(keyCode: UInt32 = UInt32(kVK_ANSI_C), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let hk = Unmanaged<HotKey>.fromOpaque(user).takeUnretainedValue()
            MainActor.assumeIsolated { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        guard status == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4156_4C45), id: 1) // 'AVLE'
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
