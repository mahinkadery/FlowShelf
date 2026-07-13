import SwiftUI
import AppKit

/// A reusable Liquid-Glass panel background: Apple's `NSGlassEffectView` (frosted
/// `.regular` style — the right one for window chrome) on macOS 26, with a
/// frosted `NSVisualEffectView` fallback on older systems. The host window should
/// be transparent (`backgroundColor = .clear`, `isOpaque = false`) so the glass
/// samples the desktop behind it.
struct GlassPanel: NSViewRepresentable {
    var cornerRadius: CGFloat = 16

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
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
            return v
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let g = nsView as? NSGlassEffectView {
            g.cornerRadius = cornerRadius
        } else {
            nsView.layer?.cornerRadius = cornerRadius
        }
    }
}

extension View {
    /// Glassmorphism treatment: a Liquid-Glass fill, a soft specular rim that reads
    /// as a glass edge, and rounded-corner clipping. Pass `strokeColor` to override
    /// the rim (e.g. an accent while a drop is targeted).
    func glassPanel(cornerRadius: CGFloat = 16, stroke: Color? = nil, strokeWidth: CGFloat = 1) -> some View {
        self
            .background(GlassPanel(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        stroke.map { AnyShapeStyle($0) }
                        ?? AnyShapeStyle(LinearGradient(
                            colors: [.white.opacity(0.38), .white.opacity(0.05), .white.opacity(0.14)],
                            startPoint: .top, endPoint: .bottom)),
                        lineWidth: strokeWidth)
            )
    }
}
