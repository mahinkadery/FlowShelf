import AppKit
import Carbon.HIToolbox
import SwiftUI

/// One recordable global shortcut: a virtual key code + Carbon modifier mask.
struct ShortcutSpec: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var mods: UInt32      // Carbon mask (cmdKey | shiftKey | optionKey | controlKey)

    /// Human string like "⌃⌥⇧⌘V", resolved against the CURRENT keyboard layout.
    var display: String { Self.modsString(mods) + Self.keyName(keyCode) }

    static func modsString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// Combo split into per-keycap symbols, e.g. ["⇧", "⌘", "V"].
    var parts: [String] {
        var p: [String] = []
        if mods & UInt32(controlKey) != 0 { p.append("⌃") }
        if mods & UInt32(optionKey) != 0 { p.append("⌥") }
        if mods & UInt32(shiftKey) != 0 { p.append("⇧") }
        if mods & UInt32(cmdKey) != 0 { p.append("⌘") }
        p.append(Self.keyName(keyCode))
        return p
    }

    /// NSEvent modifier flags → Carbon mask.
    static func carbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// CGEvent modifier flags → Carbon mask, used by the global window switcher.
    static func carbonMods(_ flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        return mods
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let specials: [UInt32: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let s = specials[keyCode] { return s }
        // Resolve character keys against the active keyboard layout.
        guard let sourceRef = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataRef = TISGetInputSourceProperty(sourceRef, kTISPropertyUnicodeKeyLayoutData)
        else { return "key\(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var deadKeys: UInt32 = 0
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

@MainActor
private enum ShortcutCaptureCoordinator {
    static func suspend() {
        HotKeyManager.shared.suspend()
        WindowSnapManager.shared.suspend()
        AltTabController.shared.suspendForShortcutCapture()
    }

    static func resume() {
        HotKeyManager.shared.resume()
        WindowSnapManager.shared.resume()
        AltTabController.shared.resumeAfterShortcutCapture()
    }
}

/// Shared click-to-record field. Esc cancels, the reset button restores the
/// default, and every shortcut engine is suspended during capture.
private struct ShortcutRecorderField: View {
    var spec: ShortcutSpec
    var defaultSpec: ShortcutSpec
    var isFailed: Bool = false
    var requiresModifier = false
    var onSet: (ShortcutSpec) -> Void
    var onReset: () -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if isFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.yellow)
                    .help("macOS refused this shortcut — another app or a system shortcut may already use it. Pick a different combo.")
            }

            if spec != defaultSpec, !recording {
                Button(action: onReset) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Reset to default (\(defaultSpec.display))")
            }

            Button(action: { recording ? cancel() : begin() }) {
                Group {
                    if recording {
                        Text("Press keys…")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10).padding(.vertical, 4.5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14)))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                            .shadow(color: Color.accentColor.opacity(0.45), radius: 5)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(Array(spec.parts.enumerated()), id: \.offset) {
                                KeyCap(symbol: $0.element,
                                       tint: hovering ? Color.accentColor : .primary)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(recording ? "Press the new shortcut (Esc to cancel)" : "Click, then press the new shortcut")
        }
        .animation(FlowMotion.state, value: recording)
        .onDisappear { if recording { cancel() } }
    }

    private func begin() {
        recording = true
        ShortcutCaptureCoordinator.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == UInt32(kVK_Escape), ShortcutSpec.carbonMods(event.modifierFlags) == 0 {
                    cancel()
                    return
                }
                let mods = ShortcutSpec.carbonMods(event.modifierFlags)
                let keyCode = UInt32(event.keyCode)
                let valid = requiresModifier ? mods != 0 : (mods != 0 || ShortcutSpec.isFunctionKey(keyCode))
                guard valid else { NSSound.beep(); return }
                onSet(ShortcutSpec(keyCode: keyCode, mods: mods))
                finish()
            }
            return nil
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        ShortcutCaptureCoordinator.resume()
    }

    private func cancel() { finish() }
}

struct ShortcutRecorder: View {
    let action: HotKeyManager.Action
    @ObservedObject private var hotkeys = HotKeyManager.shared

    var body: some View {
        ShortcutRecorderField(
            spec: hotkeys.spec(for: action),
            defaultSpec: HotKeyManager.defaultSpec(for: action),
            isFailed: hotkeys.failedActions.contains(action),
            onSet: { hotkeys.set($0, for: action) },
            onReset: { hotkeys.reset(action) }
        )
    }
}

struct WindowSnapShortcutRecorder: View {
    let zone: WindowSnapManager.Zone
    @ObservedObject private var manager = WindowSnapManager.shared

    var body: some View {
        ShortcutRecorderField(
            spec: manager.spec(for: zone),
            defaultSpec: WindowSnapManager.defaultSpec(for: zone),
            isFailed: manager.failedZones.contains(zone),
            onSet: { manager.set($0, for: zone) },
            onReset: { manager.reset(zone) }
        )
    }
}

struct AltTabShortcutRecorder: View {
    @ObservedObject private var controller = AltTabController.shared

    var body: some View {
        ShortcutRecorderField(
            spec: controller.shortcut,
            defaultSpec: AltTabController.defaultShortcut,
            requiresModifier: true,
            onSet: { controller.setShortcut($0) },
            onReset: { controller.resetShortcut() }
        )
    }
}

struct WindowSnapShortcutsEditor: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WindowSnapManager.Zone.allCases, id: \.self) { zone in
                EmblemRow(icon: zone.symbol, tint: .teal, title: zone.label,
                          caption: "Default \(WindowSnapManager.defaultSpec(for: zone).display)") {
                    WindowSnapShortcutRecorder(zone: zone)
                }
            }
        }
    }
}

/// Main app shortcuts plus one conflict report spanning app, switcher, and snap
/// bindings so a collision never looks like a broken feature.
struct ShortcutsEditor: View {
    @ObservedObject private var hotkeys = HotKeyManager.shared
    @ObservedObject private var snap = WindowSnapManager.shared
    @ObservedObject private var switcher = AltTabController.shared

    private var duplicates: [String] {
        var seen: [ShortcutSpec: [String]] = [:]
        for action in HotKeyManager.Action.allCases {
            seen[hotkeys.spec(for: action), default: []].append(action.label)
        }
        for zone in WindowSnapManager.Zone.allCases {
            seen[snap.spec(for: zone), default: []].append("Snap: \(zone.label)")
        }
        seen[switcher.shortcut, default: []].append("Window switcher")
        return seen.filter { $0.value.count > 1 }
            .map { "\($0.key.display) → " + $0.value.joined(separator: " + ") }
            .sorted()
    }

    /// Emblem icon + tint per action — each shortcut pops as its own module.
    private func emblem(for action: HotKeyManager.Action) -> (icon: String, tint: Color) {
        switch action {
        case .toggleShelf: return ("tray.full.fill", .cyan)
        case .openSearch: return ("magnifyingglass", .blue)
        case .screenshot: return ("camera.viewfinder", .pink)
        case .ocr: return ("text.viewfinder", .orange)
        case .dashboard: return ("square.grid.2x2.fill", .indigo)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(HotKeyManager.Action.allCases, id: \.rawValue) { action in
                let e = emblem(for: action)
                EmblemRow(icon: e.icon, tint: e.tint, title: action.label,
                          caption: "Default \(HotKeyManager.defaultSpec(for: action).display) — click the keys to change") {
                    ShortcutRecorder(action: action)
                }
            }

            if !duplicates.isEmpty {
                Label(
                    "Same shortcut used twice: \(duplicates.joined(separator: " · ")). Only one action will fire — change one of them.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
            if !hotkeys.failedActions.isEmpty || !snap.failedZones.isEmpty {
                Label(
                    "Shortcuts marked ⚠︎ were refused by macOS — the combo is likely taken by the system or another app.",
                    systemImage: "info.circle")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
        }
    }
}
