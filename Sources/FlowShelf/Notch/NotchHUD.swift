import SwiftUI

/// A transient "live activity" shown briefly in the collapsed notch — volume,
/// brightness, charging and low-battery. Flanks the camera notch: an icon on the
/// leading side, a level bar or percentage trailing.
enum NotchHUD: Equatable {
    case volume(Double, muted: Bool)
    case brightness(Double)
    case charging(percent: Int, charging: Bool, full: Bool)
    case lowBattery(percent: Int)

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
        }
    }
    /// 0…1 fill for the bar (volume/brightness) or ring (battery).
    var level: Double {
        switch self {
        case .volume(let v, _): return v
        case .brightness(let v): return v
        case .charging(let p, _, _): return Double(p) / 100
        case .lowBattery(let p): return Double(p) / 100
        }
    }
    var tint: Color {
        switch self {
        case .lowBattery: return .red
        case .charging: return Color(red: 0.30, green: 0.85, blue: 0.39)
        default: return .white
        }
    }
    /// Battery HUDs show a percentage; volume/brightness show a bar.
    var isBattery: Bool {
        if case .charging = self { return true }
        if case .lowBattery = self { return true }
        return false
    }
}

/// The collapsed-notch HUD content, flanking the camera notch.
struct NotchHUDView: View {
    let hud: NotchHUD
    var notchWidth: CGFloat
    var height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: hud.icon)
                .font(.system(size: min(height - 14, 13), weight: .semibold))
                .foregroundStyle(hud.tint)
                .frame(width: 22, alignment: .center)
                .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            trailing
                .padding(.trailing, 13)
        }
        .frame(height: height)
        .transition(.opacity)
    }

    @ViewBuilder private var trailing: some View {
        if hud.isBattery {
            Text("\(Int((hud.level * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(hud.tint)
        } else {
            // Slim level bar for volume / brightness.
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(hud.tint)
                    .frame(width: max(4, 74 * CGFloat(min(max(hud.level, 0), 1))))
            }
            .frame(width: 74, height: 4)
            .animation(.easeOut(duration: 0.12), value: hud.level)
        }
    }
}
