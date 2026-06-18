import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey.
/// Works without Accessibility permission (unlike NSEvent global monitors for keys).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    enum Action: UInt32, CaseIterable {
        case toggleShelf = 1     // ⌘⇧S
        case openSearch = 2      // ⌘⇧V
        case screenshot = 3      // ⌘⇧7
        case ocr = 4             // ⌘⇧O
        case dashboard = 5       // ⌘⇧D
    }

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    var onAction: ((Action) -> Void)?

    private let signature: OSType = {
        let s = "FLSF"
        return s.utf16.reduce(0) { ($0 << 8) + OSType($1) }
    }()

    private init() {}

    func registerDefaults() {
        installHandler()
        let cmdShift = UInt32(cmdKey | shiftKey)
        register(id: Action.toggleShelf.rawValue, keyCode: UInt32(kVK_ANSI_S), mods: cmdShift)
        register(id: Action.openSearch.rawValue,  keyCode: UInt32(kVK_ANSI_V), mods: cmdShift)
        register(id: Action.screenshot.rawValue,  keyCode: UInt32(kVK_ANSI_7), mods: cmdShift)
        register(id: Action.ocr.rawValue,         keyCode: UInt32(kVK_ANSI_O), mods: cmdShift)
        register(id: Action.dashboard.rawValue,   keyCode: UInt32(kVK_ANSI_D), mods: cmdShift)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Only handle our own hotkeys; otherwise let the event fall through to
            // other registered handlers (e.g. the window snapper, whose ids overlap).
            guard hkID.signature == manager.signature, let action = Action(rawValue: hkID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { manager.onAction?(action) }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    private func register(id: UInt32, keyCode: UInt32, mods: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, mods, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            refs.append(ref)
        } else {
            NSLog("FlowShelf: failed to register hotkey \(id) (status \(status))")
        }
    }

    func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
}
