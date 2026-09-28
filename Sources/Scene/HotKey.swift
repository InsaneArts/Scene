import AppKit
import Carbon.HIToolbox
import SceneSwitcher

/// Registers global shortcuts with Carbon's RegisterEventHotKey. This API needs no Accessibility or
/// Input Monitoring permission; macOS delivers only the registered combinations to Scene.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    /// Registers `spec` under `id`, replacing what `id` had. Returns a message when macOS refuses it.
    func register(_ spec: HotKeySpec, id: UInt32, action: @escaping () -> Void) -> String? {
        unregister(id)
        guard spec.isAllowed else { return "A shortcut needs ⌘ or ⌃." }
        installHandlerOnce()
        var modifiers: UInt32 = 0
        if spec.command { modifiers |= UInt32(cmdKey) }
        if spec.control { modifiers |= UInt32(controlKey) }
        if spec.option { modifiers |= UInt32(optionKey) }
        if spec.shift { modifiers |= UInt32(shiftKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x53434E45), id: id)   // "SCNE"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr:
            hotKeys[id] = ref
            actions[id] = action
            return nil
        case OSStatus(eventHotKeyExistsErr): return "\(spec.display) is already in use."
        default: return "macOS refused \(spec.display) (error \(status))."
        }
    }

    func unregister(_ id: UInt32) {
        if let ref = hotKeys.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    func unregisterAll() { hotKeys.keys.forEach(unregister) }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            // Carbon calls application-target handlers on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

extension Optional where Wrapped == HotKeySpec {
    /// "  ⌃⇧⌘Space" for a menu item's title, or nothing when the shortcut is off.
    var menuSuffix: String { map { "  \($0.display)" } ?? "" }
}
