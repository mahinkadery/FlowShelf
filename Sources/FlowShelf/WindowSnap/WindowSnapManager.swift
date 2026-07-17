import AppKit
import Carbon.HIToolbox

/// Magnet-style window snapping. Global ⌃⌥ + key shortcuts move/resize the
/// frontmost window into halves, quarters, maximize, or center on its screen.
/// Opt-in (off by default) and needs Accessibility. Self-contained Carbon hotkey
/// registration so it can start/stop independently of the app's other shortcuts.
@MainActor
final class WindowSnapManager: ObservableObject {
    static let shared = WindowSnapManager()

    enum Zone: UInt32, CaseIterable, Codable, Hashable {
        case leftHalf = 1, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center

        var label: String {
            switch self {
            case .leftHalf: return "Left half"
            case .rightHalf: return "Right half"
            case .topHalf: return "Top half"
            case .bottomHalf: return "Bottom half"
            case .topLeft: return "Top-left quarter"
            case .topRight: return "Top-right quarter"
            case .bottomLeft: return "Bottom-left quarter"
            case .bottomRight: return "Bottom-right quarter"
            case .maximize: return "Maximize"
            case .center: return "Center"
            }
        }

        var symbol: String {
            switch self {
            case .leftHalf: return "rectangle.lefthalf.inset.filled"
            case .rightHalf: return "rectangle.righthalf.inset.filled"
            case .topHalf: return "rectangle.tophalf.inset.filled"
            case .bottomHalf: return "rectangle.bottomhalf.inset.filled"
            case .topLeft: return "rectangle.inset.topleft.filled"
            case .topRight: return "rectangle.inset.topright.filled"
            case .bottomLeft: return "rectangle.inset.bottomleft.filled"
            case .bottomRight: return "rectangle.inset.bottomright.filled"
            case .maximize: return "rectangle.inset.filled"
            case .center: return "rectangle.center.inset.filled"
            }
        }

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
    private var suspended = false
    private var specs: [Zone: ShortcutSpec]

    @Published private(set) var failedZones: Set<Zone> = []
    @Published private(set) var revision = 0

    private let signature: OSType = {
        "FLSW".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    }()

    private static let defaultsKey = "windowSnapHotkeys"

    private init() {
        specs = Self.load()
    }

    static func defaultSpec(for zone: Zone) -> ShortcutSpec {
        let mods = UInt32(controlKey | optionKey)
        switch zone {
        case .leftHalf: return ShortcutSpec(keyCode: UInt32(kVK_LeftArrow), mods: mods)
        case .rightHalf: return ShortcutSpec(keyCode: UInt32(kVK_RightArrow), mods: mods)
        case .topHalf: return ShortcutSpec(keyCode: UInt32(kVK_UpArrow), mods: mods)
        case .bottomHalf: return ShortcutSpec(keyCode: UInt32(kVK_DownArrow), mods: mods)
        case .topLeft: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_U), mods: mods)
        case .topRight: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_I), mods: mods)
        case .bottomLeft: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_J), mods: mods)
        case .bottomRight: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_K), mods: mods)
        case .maximize: return ShortcutSpec(keyCode: UInt32(kVK_Return), mods: mods)
        case .center: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_C), mods: mods)
        }
    }

    func spec(for zone: Zone) -> ShortcutSpec {
        specs[zone] ?? Self.defaultSpec(for: zone)
    }

    func set(_ spec: ShortcutSpec, for zone: Zone) {
        specs[zone] = spec
        persist()
        if running { registerAll() }
        revision += 1
    }

    func reset(_ zone: Zone) {
        specs.removeValue(forKey: zone)
        persist()
        if running { registerAll() }
        revision += 1
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(specs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load() -> [Zone: ShortcutSpec] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([Zone: ShortcutSpec].self, from: data)
        else { return [:] }
        return stored
    }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        installHandler()
        registerAll()
    }

    func stop() {
        running = false
        unregisterAll()
        failedZones = []
    }

    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        if running { registerAll() }
    }

    private func registerAll() {
        unregisterAll()
        guard running, !suspended else { return }
        var failed: Set<Zone> = []
        for zone in Zone.allCases where !register(zone, spec(for: zone)) {
            failed.insert(zone)
        }
        failedZones = failed
    }

    private func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
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
        Haptics.snap()
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

    private func register(_ zone: Zone, _ spec: ShortcutSpec) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: zone.rawValue)
        let status = RegisterEventHotKey(spec.keyCode, spec.mods, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            refs.append(ref)
            return true
        }
        NSLog("FlowShelf: window-snap hotkey \(zone.rawValue) failed (status \(status))")
        return false
    }
}
