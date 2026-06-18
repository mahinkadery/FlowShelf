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
        let hosting = NSHostingController(rootView: DashboardView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "FlowShelf"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = false
        win.setContentSize(NSSize(width: 820, height: 520))
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
