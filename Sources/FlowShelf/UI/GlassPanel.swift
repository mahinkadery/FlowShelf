import SwiftUI
import AppKit

/// A reusable Liquid-Glass panel background: Apple's `NSGlassEffectView` (frosted
/// `.regular` style — the right one for window chrome) on macOS 26, with a
/// frosted `NSVisualEffectView` fallback on older systems. The host window should
/// be transparent (`backgroundColor = .clear`, `isOpaque = false`) so the glass
/// samples the desktop behind it.
/// Mirrors the system "Reduce transparency" accessibility setting live. Every
/// custom glass surface in the app must honor it — users who set it are telling
/// us they can't read text over translucency.
@MainActor
final class AccessibilityGlass: ObservableObject {
    static let shared = AccessibilityGlass()
    @Published private(set) var reduceTransparency: Bool

    private init() {
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AccessibilityGlass.shared.reduceTransparency =
                        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                }
            }
    }
}

struct GlassPanel: NSViewRepresentable {
    enum Style {
        /// Apple Liquid Glass (denser, adaptive) — window-chrome feel.
        case liquid
        /// Foggy translucency (HUD material) — see-through, softly blurred.
        case frosted
    }

    var cornerRadius: CGFloat = 16
    var style: Style = .liquid
    /// 0…1 strength of the frost. 1 = full material; lower values fade the
    /// blur/fog so the surface reads as thin, mostly-clear glass.
    var frost: CGFloat = 1.0

    func makeNSView(context: Context) -> NSView {
        if style == .liquid, #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.style = .regular
            g.cornerRadius = cornerRadius
            return g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow
            v.state = .active
            v.wantsLayer = true
            v.layer?.cornerRadius = cornerRadius
            v.layer?.masksToBounds = true
            v.alphaValue = frost
            return v
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let g = nsView as? NSGlassEffectView {
            g.cornerRadius = cornerRadius
        } else {
            nsView.layer?.cornerRadius = cornerRadius
            nsView.alphaValue = frost
        }
    }
}

/// Glassmorphism treatment: a Liquid-Glass fill, a soft specular rim that reads
/// as a glass edge, and rounded-corner clipping. Honors Reduce Transparency by
/// swapping the glass for a solid dark panel.
private struct GlassPanelModifier: ViewModifier {
    @ObservedObject private var a11y = AccessibilityGlass.shared
    var cornerRadius: CGFloat
    var style: GlassPanel.Style
    var stroke: Color?
    var strokeWidth: CGFloat
    var frost: CGFloat = 1.0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if a11y.reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    GlassPanel(cornerRadius: cornerRadius, style: style, frost: frost)
                    // A whisper of dark scrim keeps text readable on bright
                    // desktops when the frost is dialed way down.
                    if frost < 0.5 {
                        shape.fill(Color.black.opacity(0.10))
                    }
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    stroke.map { AnyShapeStyle($0) }
                    ?? AnyShapeStyle(LinearGradient(
                        colors: [.white.opacity(0.38), .white.opacity(0.05), .white.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom)),
                    lineWidth: strokeWidth)
            )
    }
}

/// The picker/panel surface: Apple's OFFICIAL SwiftUI Liquid Glass on macOS 26
/// (`.glassEffect` — includes the system's own edge treatment and adaptivity),
/// our AppKit glass on older systems, and a solid panel under Reduce Transparency.
private struct LiquidGlassSurface: ViewModifier {
    @ObservedObject private var a11y = AccessibilityGlass.shared
    var cornerRadius: CGFloat
    var tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if a11y.reduceTransparency {
            content
                .background(shape.fill(Color(red: 0.13, green: 0.13, blue: 0.14)))
                .clipShape(shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(tint)
                .modifier(GlassPanelModifier(cornerRadius: cornerRadius, style: .liquid,
                                             stroke: nil, strokeWidth: 1))
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16, style: GlassPanel.Style = .liquid,
                    stroke: Color? = nil, strokeWidth: CGFloat = 1,
                    frost: CGFloat = 1.0) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, style: style,
                                    stroke: stroke, strokeWidth: strokeWidth,
                                    frost: frost))
    }

    /// Apple-native liquid glass surface (dark, CC-style) with graceful fallbacks.
    func liquidGlassSurface(cornerRadius: CGFloat = 22, tint: Color = .black.opacity(0.35)) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Apple's interactive glass (hover/press glow) on a circular control —
    /// macOS 26 only; a no-op elsewhere or under Reduce Transparency.
    @ViewBuilder
    func interactiveGlassCircle() -> some View {
        if #available(macOS 26.0, *),
           !AccessibilityGlass.shared.reduceTransparency {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
    }
}
