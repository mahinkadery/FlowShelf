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

    func show(section: DashboardSection? = nil) {
        // Any path into the dashboard retires the menu-bar "full app →" hint.
        UserDefaults.standard.set(true, forKey: "hasOpenedDashboard")
        if window == nil { makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let section {
            UserDefaults.standard.set(section.rawValue, forKey: "dashboardLastSection")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .flowShelfDashboardSection, object: section.rawValue)
            }
        }
    }

    private func makeWindow() {
        let hosting = NSHostingView(rootView: DashboardView())
        let rootView: NSView

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = hosting
            rootView = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .underWindowBackground
            material.blendingMode = .behindWindow
            material.state = .active
            hosting.frame = material.bounds
            hosting.autoresizingMask = [.width, .height]
            material.addSubview(hosting)
            rootView = material
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "FlowShelf"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = rootView
        win.minSize = NSSize(width: 820, height: 540)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.identifier = NSUserInterfaceItemIdentifier("FlowShelfDashboard")
        let restoredFrame = win.setFrameUsingName("FlowShelfDashboard")
        _ = win.setFrameAutosaveName("FlowShelfDashboard")
        if !restoredFrame { win.center() }
        window = win
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only once the dashboard is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}

extension Notification.Name {
    static let flowShelfDashboardSection = Notification.Name("FlowShelfDashboardSection")
}
