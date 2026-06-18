import SwiftUI
import AppKit

@main
struct FlowShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        // No windows — FlowShelf lives in the menu bar (LSUIElement).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Hidden debug path: `FlowShelf --scan /Applications/Foo.app` prints the
        // Cleaner scan and exits. Used for validating the engine without the UI.
        if let idx = CommandLine.arguments.firstIndex(of: "--scan"),
           idx + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
            let r = CleanerEngine.scan(appURL: url)
            print("App: \(r.appName)  bundleID: \(r.bundleID ?? "?")  version: \(r.version ?? "?")")
            print("Found \(r.items.count) items, \(formatBytes(r.totalSize)) total")
            for (cat, files) in r.grouped() {
                print("\n[\(cat.label)]")
                for f in files {
                    print("  \(f.confidence.label.padding(toLength: 6, withPad: " ", startingAt: 0)) \(formatBytes(f.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(f.path)")
                }
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--windows") {
            print("Accessibility trusted: \(Permissions.hasAccessibility)")
            print("Screen Recording: \(Permissions.hasScreenRecording)")
            Task {
                let apps = await WindowService.shared.allAppWindows(thumbnails: false)
                print("Apps with windows (AX enumeration): \(apps.count)")

                // Capture-API check that doesn't need Accessibility: grab on-screen
                // window ids via CGWindowList and try the CGS capture on them.
                print("--- CGS capture self-test (via CGWindowList) ---")
                let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]] ?? []
                var tested = 0
                for w in info {
                    guard (w[kCGWindowLayer as String] as? Int) == 0,
                          let num = w[kCGWindowNumber as String] as? UInt32,
                          let owner = w[kCGWindowOwnerName as String] as? String,
                          owner != "FlowShelf" else { continue }
                    if let img = WindowService.shared.captureWindow(windowID: num, maxDimension: 600) {
                        let p = "/tmp/flowshelf-capture-\(num).png"
                        try? img.pngData()?.write(to: URL(fileURLWithPath: p))
                        print("  \(owner): captured \(Int(img.size.width))x\(Int(img.size.height)) → \(p)")
                    } else {
                        print("  \(owner): capture FAILED")
                    }
                    tested += 1
                    if tested >= 3 { break }
                }

                var savedOne = false
                for a in apps {
                    print("  \(a.appName) [pid \(a.pid)] — \(a.windows.count) window(s)")
                    for w in a.windows.prefix(4) {
                        var note = ""
                        if let img = WindowService.shared.captureWindow(windowID: w.id, maxDimension: 600) {
                            note = "  [captured \(Int(img.size.width))x\(Int(img.size.height))]"
                            if !savedOne, let png = img.pngData() {
                                let p = "/tmp/flowshelf-capture.png"
                                try? png.write(to: URL(fileURLWithPath: p))
                                note += " → saved \(p)"
                                savedOne = true
                            }
                        } else {
                            note = "  [capture FAILED]"
                        }
                        print("      • \(w.title)  (id \(w.id))\(note)")
                    }
                }
                exit(0)
            }
            return
        }

        if CommandLine.arguments.contains("--dashboard") {
            // (status item set up below, then jump to the dashboard)
            setupStatusItem(); setupPopover(); ClipboardMonitor.shared.start()
            DashboardWindowController.shared.show()
            return
        }
        #endif

        setupStatusItem()
        setupPopover()

        ClipboardMonitor.shared.start()
        UpdaterManager.shared.start()   // Sparkle: background update checks

        // Reflect the real login-item state (the user may have changed it elsewhere).
        AppSettings.shared.launchAtLogin = LoginItem.isEnabled

        HotKeyManager.shared.onAction = { [weak self] action in
            self?.handle(action)
        }
        HotKeyManager.shared.registerDefaults()

        // Shake-to-summon the floating shelf (Dropover-style).
        ShakeDetector.shared.onShake = { FloatingShelfController.shared.show() }
        if AppSettings.shared.shakeToSummon { ShakeDetector.shared.start() }

        // Resume Dock previews if the user had them on (and perms are still granted).
        if AppSettings.shared.dockPreviewsEnabled, Permissions.hasAccessibility {
            DockObserver.shared.start()
        }
        // Resume the Option+Tab window switcher if enabled.
        if AppSettings.shared.altTabEnabled, Permissions.hasAccessibility {
            AltTabController.shared.start()
        }
        // Resume window snapping if enabled.
        if AppSettings.shared.windowSnapEnabled, Permissions.hasAccessibility {
            WindowSnapManager.shared.start()
        }
        // Resume the notch shelf if enabled.
        if AppSettings.shared.notchEnabled {
            NotchController.shared.start()
        }

        // If Dock previews are on but we genuinely can't capture other apps'
        // windows (ground-truth test, not the lying preflight flag), surface the
        // system Screen Recording prompt so the user can grant it against the
        // current signing identity. Harmless if already granted.
        if AppSettings.shared.dockPreviewsEnabled, !WindowService.shared.canCaptureNow() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                Permissions.requestScreenRecording()
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage.menuBarGlyph(height: 18)
                ?? NSImage(systemSymbolName: "tray.full", accessibilityDescription: "FlowShelf")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])   // left = shelf, right = menu
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp
            || (NSApp.currentEvent?.modifierFlags.contains(.control) ?? false) {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    /// Right-click / Control-click menu so the full app is discoverable.
    private func showStatusMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self; return i
        }
        menu.addItem(item("Open App (Dashboard)", #selector(menuOpenDashboard)))
        menu.addItem(item("Open Shelf", #selector(menuOpenShelf)))

        // Quick "Copy Snippet ▸" submenu — paste-ready text without opening the app.
        let snippets = SnippetStore.shared.snippets
        if !snippets.isEmpty {
            let parent = NSMenuItem(title: "Copy Snippet", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for s in snippets.prefix(20) {
                let mi = NSMenuItem(title: s.title, action: #selector(menuCopySnippet(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = s.id.uuidString
                sub.addItem(mi)
            }
            menu.addItem(parent)
            menu.setSubmenu(sub, for: parent)
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit FlowShelf", #selector(menuQuit), key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil                  // restore left-click action
    }

    @objc private func menuOpenDashboard() { closePopover(); DashboardWindowController.shared.show() }
    @objc private func menuOpenShelf() { showPopover() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuCopySnippet(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let s = SnippetStore.shared.snippets.first(where: { $0.id == id }) else { return }
        SnippetStore.shared.copy(s)
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc private func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() { popover.performClose(nil) }

    // MARK: - Hotkeys

    private func handle(_ action: HotKeyManager.Action) {
        switch action {
        case .toggleShelf:
            FloatingShelfController.shared.toggle()
        case .openSearch:
            showPopover()
        case .screenshot:
            ScreenshotService.shared.captureRegion(runOCR: false)
        case .ocr:
            ScreenshotService.shared.captureRegion(runOCR: true)
        case .dashboard:
            closePopover()
            DashboardWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
        ClipboardMonitor.shared.stop()
    }
}
