import AppKit
import Carbon.HIToolbox

/// Magnet-style window snapping. Global ⌃⌥ + key shortcuts move/resize the
/// frontmost window into halves, quarters, maximize, or center on its screen.
/// Opt-in (off by default) and needs Accessibility. Self-contained Carbon hotkey
/// registration so it can start/stop independently of the app's other shortcuts.
@MainActor
final class WindowSnapManager {
    static let shared = WindowSnapManager()

    enum Zone: UInt32, CaseIterable {
        case leftHalf = 1, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center

        /// Target frame in Cocoa coords (bottom-left origin) within a screen's
        /// visible area (which already excludes the menu bar and Dock).
        func rect(in vf: CGRect) -> CGRect {
            let halfW = vf.width / 2, halfH = vf.height / 2
            switch self {
            case .leftHalf:    return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: vf.height)
            case .rightHalf:   return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: vf.height)
            case .topHalf:     return CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: halfH)
            case .bottomHalf:  return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: halfH)
            case .topLeft:     return CGRect(x: vf.minX, y: vf.midY, width: halfW, height: halfH)
            case .topRight:    return CGRect(x: vf.midX, y: vf.midY, width: halfW, height: halfH)
            case .bottomLeft:  return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: halfH)
            case .bottomRight: return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: halfH)
            case .maximize:    return vf
            case .center:
                let w = vf.width * 0.7, h = vf.height * 0.8
                return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
            }
        }
    }

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private(set) var running = false

    private let signature: OSType = {
        "FLSW".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    }()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        installHandler()
        let mods = UInt32(controlKey | optionKey)
        register(.leftHalf,    kVK_LeftArrow,  mods)
        register(.rightHalf,   kVK_RightArrow, mods)
        register(.topHalf,     kVK_UpArrow,    mods)
        register(.bottomHalf,  kVK_DownArrow,  mods)
        register(.topLeft,     kVK_ANSI_U,     mods)
        register(.topRight,    kVK_ANSI_I,     mods)
        register(.bottomLeft,  kVK_ANSI_J,     mods)
        register(.bottomRight, kVK_ANSI_K,     mods)
        register(.maximize,    kVK_Return,     mods)
        register(.center,      kVK_ANSI_C,     mods)
        running = true
    }

    func stop() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
        running = false
    }

    // MARK: - Snapping

    func snap(_ zone: Zone) {
        guard let win = AX.focusedWindow(), let axFrame = AX.frame(of: win) else { return }
        let cocoaFrame = AX.flipY(axFrame)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        AX.setFrame(win, AX.flipY(zone.rect(in: vf)))
    }

    // MARK: - Carbon plumbing

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<WindowSnapManager>.fromOpaque(userData).takeUnretainedValue()
            // Only our own hotkeys — otherwise pass through (the app's ⌘⇧ hotkeys
            // share ids 1–5 with our zones; checking the signature avoids hijacking
            // them).
            guard hkID.signature == manager.signature, let zone = Zone(rawValue: hkID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { manager.snap(zone) }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    private func register(_ zone: Zone, _ keyCode: Int, _ mods: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: zone.rawValue)
        let status = RegisterEventHotKey(UInt32(keyCode), mods, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { refs.append(ref) }
        else { NSLog("FlowShelf: window-snap hotkey \(zone.rawValue) failed (status \(status))") }
    }
}
