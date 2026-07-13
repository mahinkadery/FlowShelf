import SwiftUI
import AppKit

/// FlowShelf's motion system — every animation in the app should come from here.
///
/// Three rules make the app feel native:
/// 1. Asymmetric expand/collapse: opening gets a lively spring, closing is
///    critically damped so it lands with zero wobble.
/// 2. The environment is respected: Reduce Motion swaps springs for short eases,
///    Low Power Mode and 60Hz panels skip expensive blur work, and durations
///    stretch slightly on low-refresh displays so frame-stepping is less visible.
/// 3. No magic numbers at call sites — views name the *intent* (`.expandOpen`,
///    `.press`, `.listChange`) and tuning lives here.
enum FlowMotion {

    // MARK: - Environment

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var lowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Refresh rate of the screen the pointer is on (falls back to main).
    private static var pointerScreenFPS: Int {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return max(screen?.maximumFramesPerSecond ?? 60, 60)
    }

    /// Stretch durations a touch on lower-refresh panels; high-refresh runs 1:1.
    private static var timeScale: Double {
        let fps = pointerScreenFPS
        if fps >= 100 { return 1.0 }
        if fps >= 75 { return 1.1 }
        return 1.18
    }

    private static func t(_ base: Double) -> Double { base * timeScale }

    /// Skip blur-heavy effects when the GPU budget is tight or motion is reduced.
    static var lightweightEffects: Bool {
        reduceMotion || lowPower || pointerScreenFPS <= 60
    }

    // MARK: - Expand / collapse (asymmetric)

    /// Panels, shelves and the notch opening: a lively spring with a visible
    /// Control-Centre-style overshoot before it settles.
    static var expandOpen: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.26))
            : .spring(response: t(0.44), dampingFraction: 0.70, blendDuration: 0)
    }

    /// The same surfaces closing: critically damped, no bounce-back.
    static var expandClose: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.24))
            : .spring(response: t(0.36), dampingFraction: 0.97, blendDuration: 0)
    }

    // MARK: - Hover & press

    /// Hover on cards, tiles and buttons.
    static var hover: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.14))
            : .spring(response: t(0.28), dampingFraction: 0.82)
    }

    /// Subtle grow-on-hover for the notch pill / large surfaces.
    static var hoverScale: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.12))
            : .spring(response: t(0.36), dampingFraction: 0.90, blendDuration: 0)
    }

    /// Press-down: immediate.
    static var press: Animation {
        .interactiveSpring(response: t(0.14), dampingFraction: 0.82)
    }

    /// Release: settles with a small natural bounce.
    static var release: Animation {
        .spring(response: t(0.24), dampingFraction: 0.74)
    }

    // MARK: - State & content

    /// Toggles, selections, mode switches.
    static var state: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.18))
            : .spring(response: t(0.24), dampingFraction: 0.82)
    }

    /// Pins, favorites — a touch more bounce so the change registers.
    static var stateEmphasis: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.20))
            : .spring(response: t(0.28), dampingFraction: 0.72)
    }

    /// Inserting / removing / reordering list & grid items.
    static var listChange: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.20))
            : .spring(response: t(0.26), dampingFraction: 0.84)
    }

    /// Sheets, popovers, panels.
    static var transition: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.24))
            : .spring(response: t(0.34), dampingFraction: 0.88)
    }

    /// Swapping one piece of content for another — overdamped, pure crossfade.
    static var blurReplace: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.18))
            : .interactiveSpring(dampingFraction: 1.1)
    }

    /// Smooth content movement (progress bars, layout shifts).
    static var smoothContent: Animation {
        .smooth(duration: t(0.36))
    }

    /// Playful attention bounce (copied! toasts, success ticks).
    static var bounce: Animation {
        reduceMotion
            ? .easeOut(duration: t(0.20))
            : .spring(response: t(0.18), dampingFraction: 0.56)
    }
}

// MARK: - Appear/disappear transitions

/// Scale-from-top + blur + fade: content appears to grow out of its anchor
/// (the notch, a header). Blur is dropped automatically on tight GPU budgets.
private struct FlowEmergeModifier: ViewModifier {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Signature FlowShelf entrance: grow from the top edge with a soft blur.
    static var flowEmerge: AnyTransition {
        let blur: CGFloat = FlowMotion.lightweightEffects ? 0 : 6
        return .modifier(
            active: FlowEmergeModifier(scale: 0.86, blur: blur, opacity: 0),
            identity: FlowEmergeModifier(scale: 1, blur: 0, opacity: 1)
        ).animation(FlowMotion.smoothContent)
    }

    /// Cheaper variant for dense grids — scale + fade only, never blurs.
    static var flowEmergeLight: AnyTransition {
        .modifier(
            active: FlowEmergeModifier(scale: 0.85, blur: 0, opacity: 0),
            identity: FlowEmergeModifier(scale: 1, blur: 0, opacity: 1)
        ).animation(FlowMotion.smoothContent)
    }

    /// Small controls (round buttons, badges) popping in.
    static var flowPop: AnyTransition {
        let blur: CGFloat = FlowMotion.lightweightEffects ? 0 : 3
        return .modifier(
            active: FlowEmergeModifier(scale: 0.55, blur: blur, opacity: 0),
            identity: FlowEmergeModifier(scale: 1, blur: 0, opacity: 1)
        ).animation(FlowMotion.smoothContent)
    }
}

// MARK: - View helpers

extension View {
    /// Drives an expand/collapse with the asymmetric pair: lively open,
    /// critically-damped close.
    func flowExpand(_ isOpen: Bool) -> some View {
        animation(isOpen ? FlowMotion.expandOpen : FlowMotion.expandClose, value: isOpen)
    }

    /// Hover feedback without animation stacking: update state directly in
    /// `onHover` and let a view-level animation own the motion.
    func flowHover(_ isHovering: Binding<Bool>, animation: Animation = FlowMotion.hover) -> some View {
        onHover { isHovering.wrappedValue = $0 }
            .animation(animation, value: isHovering.wrappedValue)
    }
}
