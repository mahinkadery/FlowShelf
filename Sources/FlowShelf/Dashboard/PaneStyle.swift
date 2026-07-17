import SwiftUI

/// Shared visual building blocks for dashboard panes.

/// A tinted gradient icon chip — the "emblem" that makes a row pop.
struct EmblemChip: View {
    var icon: String
    var tint: Color
    var size: CGFloat = 27
    var iconSize: CGFloat = 12.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// The frosted glass circle used by empty states across the dashboard.
struct GlassCircleBadge: View {
    var icon: String
    var tint: Color = .secondary
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.14), .clear],
                                         startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

/// A physical-looking keyboard keycap — raised glass, subtle 3D drop.
struct KeyCap: View {
    var symbol: String
    var tint: Color = .primary

    var body: some View {
        Text(symbol)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(minWidth: 13)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.05)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }
}

extension View {
    /// A quiet content-layer card. Navigation and the window own the Liquid
    /// Glass layer; keeping repeated rows simple avoids unnecessary render passes.
    func raisedCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(RaisedDashboardCard(cornerRadius: cornerRadius))
    }
}

private struct RaisedDashboardCard: ViewModifier {
    @ObservedObject private var glass = AccessibilityGlass.shared
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(glass.reduceTransparency
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color.primary.opacity(0.055))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.13), .white.opacity(0.025)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            }
    }
}
