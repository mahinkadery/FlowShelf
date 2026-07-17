import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private let completionKey = "onboardingV1Completed"
    private var window: NSWindow?
    private var isFinishing = false

    func showIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: completionKey) != nil {
            guard !defaults.bool(forKey: completionKey) else { return }
        } else if defaults.object(forKey: "firstLaunchAt") != nil {
            // Existing installs should not be interrupted after an update.
            defaults.set(true, forKey: completionKey)
            return
        }
        show(force: false)
    }

    func show(force: Bool = true) {
        if !force, UserDefaults.standard.bool(forKey: completionKey) { return }
        if window == nil { makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() {
        let view = OnboardingView { [weak self] destination in
            self?.finish(destination: destination)
        }
        let hosting = NSHostingView(rootView: view)
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
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 610),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to FlowShelf"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = rootView
        win.minSize = NSSize(width: 820, height: 560)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        window = win
    }

    private func finish(destination: OnboardingDestination) {
        isFinishing = true
        UserDefaults.standard.set(true, forKey: completionKey)
        window?.orderOut(nil)

        switch destination {
        case .none:
            if !DashboardWindowController.shared.isVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        case .shelf, .permissions:
            DashboardWindowController.shared.show(
                section: destination == .permissions ? .permissions : .shelf
            )
        }
        isFinishing = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing else { return }
        UserDefaults.standard.set(true, forKey: completionKey)
        if !DashboardWindowController.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

enum OnboardingDestination {
    case none, shelf, permissions
}
