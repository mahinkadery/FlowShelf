import SwiftUI

/// A transient "live activity" shown briefly in the collapsed notch — volume,
/// brightness, charging and low-battery. Flanks the camera notch: an icon on the
/// leading side, a level bar or percentage trailing.
enum NotchHUD: Equatable {
    case volume(Double, muted: Bool)
    case brightness(Double)
    case charging(percent: Int, charging: Bool, full: Bool)
    case lowBattery(percent: Int)
    case lowPowerMode(Bool)
    case audioRoute(name: String, icon: String, bluetooth: Bool)

    var icon: String {
        switch self {
        case .volume(let v, let muted):
            if muted || v <= 0.001 { return "speaker.slash.fill" }
            if v < 0.34 { return "speaker.wave.1.fill" }
            if v < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .charging(_, _, let full): return full ? "battery.100.bolt" : "bolt.fill"
        case .lowBattery: return "battery.25"
        case .lowPowerMode: return "battery.50"
        case .audioRoute(_, let icon, _): return icon
        }
    }
    /// 0…1 fill for the bar (volume/brightness) or ring (battery).
    var level: Double {
        switch self {
        case .volume(let v, let muted): return muted ? 0 : v
        case .brightness(let v): return v
        case .charging(let p, _, _): return Double(p) / 100
        case .lowBattery(let p): return Double(p) / 100
        case .lowPowerMode, .audioRoute: return 0
        }
    }
    var tint: Color {
        switch self {
        case .lowBattery: return .red
        case .charging: return Color(red: 0.30, green: 0.85, blue: 0.39)
        case .lowPowerMode(let enabled): return enabled ? .yellow : .white
        default: return .white
        }
    }
    /// Battery HUDs show a percentage; volume/brightness show a bar.
    var isBattery: Bool {
        if case .charging = self { return true }
        if case .lowBattery = self { return true }
        return false
    }

    var isSystemEvent: Bool {
        switch self {
        case .charging, .lowBattery, .lowPowerMode, .audioRoute: return true
        default: return false
        }
    }

    var wingWidth: CGFloat {
        switch self {
        case .audioRoute: return 58
        case .charging, .lowBattery: return 112
        case .lowPowerMode: return 124
        case .volume, .brightness: return 88
        }
    }

    var isAccessoryConnection: Bool {
        if case .audioRoute = self { return true }
        return false
    }

    static func batterySymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch max(0, min(100, percent)) {
        case 0: return "battery.0percent"
        case 1...25: return "battery.25percent"
        case 26...50: return "battery.50percent"
        case 51...75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    func presentationSize(notch: CGSize, compact: Bool = false) -> CGSize {
        if case .audioRoute = self {
            return compact
                ? CGSize(width: notch.width + 116, height: max(32, notch.height))
                : CGSize(width: max(400, notch.width + 160), height: notch.height + 72)
        }
        let minimumHeight: CGFloat = NotchAccessoryKind(symbol: icon) != nil ? 42 : 34
        return CGSize(width: notch.width + wingWidth * 2, height: max(notch.height, minimumHeight))
    }

    var title: String {
        switch self {
        case .audioRoute(let name, _, _): return name
        case .lowPowerMode: return "Low Power Mode"
        case .lowBattery: return "Low Battery"
        case .charging(_, let charging, let full): return full ? "Fully charged" : (charging ? "Charging" : "Power connected")
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        }
    }

    var detail: String {
        switch self {
        case .audioRoute(_, _, let bluetooth): return bluetooth ? "Connected for audio" : "Audio output changed"
        case .lowPowerMode(let enabled): return enabled ? "On · saving energy" : "Off · normal power"
        case .lowBattery(let percent): return "\(max(0, min(100, percent)))% remaining"
        case .charging(let percent, _, _): return "\(max(0, min(100, percent)))% battery"
        default: return ""
        }
    }
}

/// The collapsed-notch HUD content, flanking the camera notch.
struct NotchHUDView: View {
    let hud: NotchHUD
    var notchWidth: CGFloat
    var height: CGFloat
    var exiting = false
    var animated = true
    var compact = false
    var notchHeight: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var resolved = false
    @State private var completed = false

    private var visible: Bool { !animated || reduceMotion || revealed }
    private var finished: Bool { !animated || reduceMotion || completed }
    private var motion: Bool { animated && !reduceMotion }
    private var accent: Color {
        if case .audioRoute = hud { return Color(red: 0.22, green: 0.88, blue: 0.39) }
        return hud.tint
    }

    var body: some View {
        Group {
            if case .audioRoute(_, _, let bluetooth) = hud {
                VStack(spacing: 0) {
                    Color.clear.frame(height: compact ? 0 : notchHeight)
                    HStack(spacing: compact ? 0 : 14) {
                        leading
                            .scaleEffect(compact ? 0.55 : 1)
                            .frame(width: compact ? 58 : 56, height: compact ? height : 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bluetooth ? "Connected" : "Audio output")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(hud.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .opacity(compact ? 0 : 1)
                        .frame(width: compact ? notchWidth : nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        trailing.frame(width: compact ? 58 : 30, height: 30)
                    }
                    .padding(.horizontal, compact ? 0 : 20)
                    .frame(height: compact ? height : 72)
                    .offset(y: motion && (!visible || exiting) ? -6 : 0)
                }
                .frame(width: compact ? notchWidth + 116 : max(400, notchWidth + 160), height: height)
            } else {
                HStack(spacing: 0) {
                    leading
                        .frame(width: hud.wingWidth, height: height)
                        .offset(x: motion && (!visible || exiting) ? 12 : 0)
                    Color.clear.frame(width: notchWidth, height: height)
                    trailing
                        .frame(width: hud.wingWidth, height: height)
                        .offset(x: motion && (!visible || exiting) ? -12 : 0)
                }
            }
        }
        .opacity(visible && !exiting ? 1 : 0)
        .animation(motion ? .easeOut(duration: 0.16) : nil, value: exiting)
        .help("\(hud.title) — \(hud.detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .task(id: reduceMotion) {
            guard motion else {
                revealed = true
                resolved = true
                completed = true
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(65))
                withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) { revealed = true }
                try await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.48)) { resolved = true }
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { completed = true }
            } catch { return }
        }
    }

    private var accessibilityDescription: String {
        switch hud {
        case .volume(let level, let muted): return muted ? "Volume muted" : "Volume \(Int(level * 100)) percent"
        case .brightness(let level): return "Brightness \(Int(level * 100)) percent"
        default: return "\(hud.title), \(hud.detail)"
        }
    }

    @ViewBuilder private var leading: some View {
        switch hud {
        case .audioRoute:
            if let kind = NotchAccessoryKind(symbol: hud.icon),
               let artwork = NotchAccessoryAssets.poster(for: kind) {
                if animated {
                    NotchAccessoryAnimation(kind: kind, playing: motion && visible && !exiting)
                        .frame(width: 52, height: 52)
                } else {
                    Image(decorative: artwork, scale: 2)
                        .resizable().interpolation(.high)
                        .frame(width: 52, height: 52)
                }
            } else {
                Image(systemName: hud.icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(motion && !visible ? 0.5 : 1)
            }
        case .charging, .lowBattery, .lowPowerMode:
            Text(hud.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
        case .volume, .brightness:
            HUDNativeSymbol(name: hud.icon, animate: motion && !exiting, trigger: resolved)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch hud {
        case .audioRoute:
            connectionConfirmation
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
        case .charging(let percent, let charging, _):
            battery(percent: percent, charging: charging)
        case .lowBattery(let percent):
            battery(percent: percent, charging: false)
        case .lowPowerMode(let enabled):
            HStack(spacing: 7) {
                Text(enabled ? "On" : "Off")
                    .font(.system(size: 13, weight: .semibold))
                HUDNativeSymbol(name: "battery.100percent", animate: motion && !exiting, trigger: resolved)
                    .font(.system(size: 21, weight: .regular))
            }
            .foregroundStyle(accent)
        case .volume, .brightness:
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(hud.tint)
                    .frame(width: 74 * CGFloat(min(max(hud.level, 0), 1)))
            }
            .frame(width: 74, height: 4)
            .animation(motion ? .easeOut(duration: 0.12) : nil, value: hud.level)
        }
    }

    private func battery(percent: Int, charging: Bool) -> some View {
        HStack(spacing: 7) {
            Text("\(max(0, min(100, percent)))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(motion ? .numericText() : .identity)
            HUDNativeSymbol(name: NotchHUD.batterySymbol(percent: percent, charging: charging),
                            animate: motion && !exiting, trigger: resolved)
                .font(.system(size: 23, weight: .regular))
                .frame(width: 34, height: 22)
        }
        .foregroundStyle(accent)
    }

    @ViewBuilder private var connectionConfirmation: some View {
        if motion && !exiting {
            if #available(macOS 26.0, *) {
                ZStack {
                    if finished {
                        Image(systemName: "checkmark.circle")
                            .transition(.symbolEffect(.drawOn))
                    }
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .symbolEffect(.bounce, options: .nonRepeating, value: completed)
                    .opacity(finished ? 1 : 0)
            }
        } else {
            Image(systemName: "checkmark.circle")
        }
    }
}

private struct HUDNativeSymbol: View {
    let name: String
    let animate: Bool
    let trigger: Bool

    var body: some View {
        if animate {
            Image(systemName: name)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .nonRepeating, value: trigger)
        } else {
            Image(systemName: name)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
