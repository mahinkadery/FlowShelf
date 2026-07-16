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

    /// NSEvent modifier flags → Carbon mask.
    static func carbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
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

/// Click-to-record shortcut field: click, press any combo, done. Esc cancels,
/// the ↺ button restores the default. Hotkeys are suspended while recording so
/// the combo being tried never fires the action mid-capture.
struct ShortcutRecorder: View {
    let action: HotKeyManager.Action
    @ObservedObject private var hotkeys = HotKeyManager.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? cancel() : begin() }) {
                Text(recording ? "Type shortcut…" : hotkeys.spec(for: action).display)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(recording ? Color.accentColor : .primary)
                    .frame(minWidth: 76)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new shortcut (Esc to cancel)" : "Click, then press the new shortcut")

            if hotkeys.spec(for: action) != HotKeyManager.defaultSpec(for: action) {
                Button(action: { hotkeys.reset(action) }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Reset to default (\(HotKeyManager.defaultSpec(for: action).display))")
            }

            if hotkeys.failedActions.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.yellow)
                    .help("macOS refused this shortcut — another app or a system shortcut may already use it. Pick a different combo.")
            }
        }
        .onDisappear { if recording { cancel() } }
    }

    private func begin() {
        recording = true
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == UInt32(kVK_Escape), ShortcutSpec.carbonMods(event.modifierFlags) == 0 {
                    cancel()
                    return
                }
                let mods = ShortcutSpec.carbonMods(event.modifierFlags)
                let isFKey = (96...122).contains(event.keyCode)
                // Bare letters/digits would hijack normal typing system-wide.
                guard mods != 0 || isFKey else { NSSound.beep(); return }
                hotkeys.set(ShortcutSpec(keyCode: UInt32(event.keyCode), mods: mods), for: action)
                finish()
            }
            return nil   // swallow the keystroke while recording
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hotkeys.resume()
    }

    private func cancel() { finish() }
}

/// The Settings block: one recorder row per action, plus duplicate detection
/// inside FlowShelf and a warning when macOS refuses a combo.
struct ShortcutsEditor: View {
    @ObservedObject private var hotkeys = HotKeyManager.shared

    /// Combos used by more than one action right now.
    private var duplicates: [String] {
        var seen: [ShortcutSpec: [HotKeyManager.Action]] = [:]
        for a in HotKeyManager.Action.allCases { seen[hotkeys.spec(for: a), default: []].append(a) }
        return seen.filter { $0.value.count > 1 }
            .map { "\($0.key.display) → " + $0.value.map(\.label).joined(separator: " + ") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(HotKeyManager.Action.allCases, id: \.rawValue) { action in
                HStack {
                    Text(action.label).font(.system(size: 12))
                    Spacer()
                    ShortcutRecorder(action: action)
                }
            }

            if !duplicates.isEmpty {
                Label(
                    "Same shortcut used twice: \(duplicates.joined(separator: " · ")). Only one action will fire — change one of them.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hotkeys.failedActions.isEmpty {
                Label(
                    "Shortcuts marked ⚠︎ were refused by macOS — the combo is likely taken by the system or another app.",
                    systemImage: "info.circle")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Click a shortcut, then press any key combination. Esc cancels, ↺ restores the default.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}
