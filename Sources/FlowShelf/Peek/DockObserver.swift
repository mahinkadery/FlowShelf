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
/// marks the hovered Dock item as the list's "selected child". A light timer
/// handles dismissal with hysteresis so the preview survives the gap between the
/// icon and the popover.
@MainActor
final class DockObserver {
    static let shared = DockObserver()

    private var dockPID: pid_t?
    private var axObserver: AXObserver?
    private var subscribedList: AXUIElement?
    private var hideTimer: Timer?

    private let preview = DockPreviewController()
    private var currentPID: pid_t?
    private var currentIconFrameCG: CGRect?         // CoreGraphics top-left
    private var leftRegionSince: Date?
    private let hideDelay: TimeInterval = 0.28

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
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickHide() }
        }
    }

    func stop() {
        isRunning = false
        hideTimer?.invalidate(); hideTimer = nil
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                  AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
        subscribedList = nil
        preview.hide()
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
            // Hovered off any app icon — let the hide timer take it down.
            leftRegionSince = leftRegionSince ?? Date()
            return
        }

        guard let app = runningApp(for: item) else { return }
        let frame = AX.frame(of: item)
        currentPID = app.processIdentifier
        currentIconFrameCG = frame
        leftRegionSince = nil

        preview.present(pid: app.processIdentifier,
                        appName: app.localizedName ?? "App",
                        icon: app.icon,
                        bundleID: app.bundleIdentifier,
                        iconFrameCG: frame ?? .zero,
                        dockPosition: DockPosition.current)
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

    // MARK: - Dismissal (hysteresis)

    private func tickHide() {
        guard preview.isVisible else { return }
        let mouse = CGEvent(source: nil)?.location ?? .zero   // CG top-left

        let overIcon = (currentIconFrameCG?.insetBy(dx: -6, dy: -10).contains(mouse)) ?? false
        let overPanel = preview.containsMouse

        if overIcon || overPanel {
            leftRegionSince = nil
            return
        }
        // Outside both — start/continue the grace period, then hide.
        let since = leftRegionSince ?? Date()
        leftRegionSince = since
        if Date().timeIntervalSince(since) >= hideDelay {
            preview.hide()
            currentPID = nil
            currentIconFrameCG = nil
            leftRegionSince = nil
        }
    }
}
