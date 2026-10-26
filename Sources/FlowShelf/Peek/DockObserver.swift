import AppKit
import ApplicationServices

/// C-level AXObserver callback → forwards to the DockObserver instance.
private func dockSelectionCallback(_ observer: AXObserver, _ element: AXUIElement,
                                   _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let obs = Unmanaged<DockObserver>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { obs.handleSelectionChanged() }
}

/// Detects which Dock icon the pointer is over and shows a live window preview.
///
/// Instead of polling the mouse and hit-testing icon rectangles (fragile), we
/// subscribe to the Dock's `kAXSelectedChildrenChangedNotification`: macOS itself
/// marks the hovered Dock item as the list's "selected child".
@MainActor
final class DockObserver {
    static let shared = DockObserver()

    private var dockPID: pid_t?
    private var axObserver: AXObserver?
    private var subscribedList: AXUIElement?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?

    private let preview = DockPreviewController()
    private var currentPID: pid_t?
    private var currentIconFrameCG: CGRect?         // CoreGraphics top-left
    private var showTimer: Timer?
    private var hoverToken = UUID()

    /// The Settings "hover delay" is the APPEAR delay — how long you must rest
    /// on an icon before the preview shows (skimming the Dock stays quiet).
    private var appearDelay: TimeInterval { AppSettings.shared.dockPreviewHoverDelay }

    private(set) var isRunning = false
    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning, Permissions.hasAccessibility else { return }
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock").first else { return }
        dockPID = dock.processIdentifier
        guard setupObserver() else { return }
        isRunning = true
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.checkPointer() }
            return event
        }
    }

    func stop() {
        isRunning = false
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal) }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal) }
        mouseGlobal = nil
        mouseLocal = nil
        hoverToken = UUID()
        showTimer?.invalidate(); showTimer = nil
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                  AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
        subscribedList = nil
        preview.hide(animated: false)
        currentPID = nil
        currentIconFrameCG = nil
    }

    private func setupObserver() -> Bool {
        guard let dockPID, let list = AX.dockList(dockPID: dockPID) else { return false }
        var observer: AXObserver?
        guard AXObserverCreate(dockPID, dockSelectionCallback, &observer) == .success,
              let observer else { return false }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard result == .success || result == .notificationAlreadyRegistered else { return false }

        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        subscribedList = list
        return true
    }

    // MARK: - Hover → show

    func handleSelectionChanged() {
        guard isRunning, let dockPID,
              let item = AX.selectedDockItem(dockPID: dockPID),
              AX.subrole(of: item) == "AXApplicationDockItem" else {
            if !pointerWithinPreviewRoute { dismiss() }
            return
        }

        guard let app = runningApp(for: item), let frame = AX.frame(of: item),
              let mouse = CGEvent(source: nil)?.location, frame.contains(mouse) else {
            if !pointerWithinPreviewRoute { dismiss() }
            return
        }
        if currentPID == app.processIdentifier {
            currentIconFrameCG = frame
            return
        }
        currentPID = app.processIdentifier
        currentIconFrameCG = frame
        showTimer?.invalidate(); showTimer = nil
        let token = UUID()
        hoverToken = token

        let show = { [weak self] in
            guard let self, self.isRunning, self.hoverToken == token,
                  let mouse = CGEvent(source: nil)?.location,
                  self.currentIconFrameCG?.contains(mouse) == true else { return }
            self.preview.present(pid: app.processIdentifier,
                                  appName: app.localizedName ?? "App",
                                  icon: app.icon,
                                  bundleID: app.bundleIdentifier,
                                  iconFrameCG: self.currentIconFrameCG ?? frame,
                                  dockPosition: DockPosition.current)
        }

        if preview.isVisible {
            // Already open — glide to the next icon immediately, no re-delay.
            show()
        } else {
            // First appearance: rest on the icon for the configured delay so
            // skimming across the Dock doesn't flash panels.
            let timer = Timer(timeInterval: max(appearDelay, 0.05),
                                             repeats: false) { _ in
                MainActor.assumeIsolated {
                    show()
                }
            }
            showTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Resolve the running app behind a Dock item via its file URL → bundle id,
    /// falling back to matching the item's title.
    private func runningApp(for item: AXUIElement) -> NSRunningApplication? {
        if let url = AX.url(of: item),
           let bundleID = Bundle(url: url)?.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let first = running.first { return first }
        }
        if let title = AX.title(of: item) {
            return NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.localizedName == title
            }
        }
        return nil
    }

    private func checkPointer() {
        guard isRunning, currentPID != nil else { return }
        guard !pointerWithinPreviewRoute else { return }
        if let mouse = CGEvent(source: nil)?.location {
            if currentIconFrameCG?.contains(mouse) == true { return }
            if let dockPID, let item = AX.selectedDockItem(dockPID: dockPID),
               let frame = AX.frame(of: item), frame.contains(mouse),
               runningApp(for: item)?.processIdentifier == currentPID {
                currentIconFrameCG = frame
                return
            }
        }
        dismiss()
    }

    private var pointerWithinPreviewRoute: Bool {
        preview.keepsOpen(at: NSEvent.mouseLocation, currentIconFrameCG: currentIconFrameCG)
    }

    private func dismiss() {
        hoverToken = UUID()
        showTimer?.invalidate(); showTimer = nil
        preview.hide()
        currentPID = nil
        currentIconFrameCG = nil
    }
}
