import AppKit
import SwiftUI

/// Owns the single dashboard window. While it's open, FlowShelf becomes a normal
/// app (Dock icon + Cmd-Tab + real window); when it closes, we drop back to a
/// lightweight menu-bar agent.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil { makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func makeWindow() {
        // Frosted-glass window (canonical vibrant-window pattern): an
        // NSVisualEffectView *is* the content view, with the SwiftUI UI hosted on
        // top. `.underWindowBackground` gives a translucent, foggy backdrop that
        // stays readable — the content clears its List backgrounds so the frost
        // shows through, but text/icons remain fully opaque.
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        let hosting = NSHostingView(rootView: DashboardView())
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "FlowShelf"
        win.titlebarAppearsTransparent = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = effect
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.identifier = NSUserInterfaceItemIdentifier("FlowShelfDashboard")
        window = win
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only once the dashboard is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}
