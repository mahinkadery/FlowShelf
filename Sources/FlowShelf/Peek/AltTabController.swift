import AppKit
import SwiftUI
import Carbon.HIToolbox

/// C event-tap callback → forwards to the controller (runs on the main run loop,
/// so we're already on the main actor).
private func altTabEventCallback(proxy: CGEventTapProxy, type: CGEventType,
                                 event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<AltTabController>.fromOpaque(userInfo).takeUnretainedValue()
    let consumed = MainActor.assumeIsolated { controller.handle(type: type, event: event) }
    return consumed ? nil : Unmanaged.passUnretained(event)
}

/// Option+Tab window switcher (AltTab/DockDoor style). A `CGEventTap` intercepts
/// Option+Tab to show an overlay of live window previews; arrows/Tab navigate;
/// releasing Option (or Return) switches; Esc cancels.
@MainActor
final class AltTabController {
    static let shared = AltTabController()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    private var active = false
    private let model = AltTabModel()
    private var overlay: NSPanel?

    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !isRunning, Permissions.hasAccessibility else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: altTabEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil; runLoopSource = nil
        cancel()
        isRunning = false
    }

    // MARK: Event handling (returns true to consume the event)

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)

        if type == .flagsChanged {
            if active && !optionDown { commit() }   // released Option → switch
            return false
        }

        guard type == .keyDown else { return false }
        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if optionDown && keycode == kVK_Tab {
            let reverse = flags.contains(.maskShift)
            active ? advance(reverse: reverse) : begin(reverse: reverse)
            return true
        }

        guard active else { return false }
        switch keycode {
        case kVK_Escape:                        cancel();              return true
        case kVK_RightArrow, kVK_DownArrow:     advance(reverse: false); return true
        case kVK_LeftArrow, kVK_UpArrow:        advance(reverse: true);  return true
        case kVK_Return, kVK_ANSI_KeypadEnter:  commit();              return true
        default:                                return false
        }
    }

    // MARK: Switcher logic

    private func begin(reverse: Bool) {
        let wins = orderedWindows()
        guard !wins.isEmpty else { return }
        active = true
        model.layout = AppSettings.shared.altTabLayout
        model.windows = wins
        // Start on the *previous* window (classic alt-tab), or last if reversing.
        model.selectedIndex = reverse ? wins.count - 1 : min(1, wins.count - 1)
        showOverlay()
        captureThumbnails()
    }

    private func advance(reverse: Bool) {
        guard active, !model.windows.isEmpty else { return }
        let n = model.windows.count
        model.selectedIndex = ((model.selectedIndex + (reverse ? -1 : 1)) % n + n) % n
    }

    private func commit() {
        guard active else { return }
        active = false
        let win = model.windows.indices.contains(model.selectedIndex) ? model.windows[model.selectedIndex] : nil
        hideOverlay()
        if let win { AX.raiseWindow(pid: win.pid, windowID: win.id) }
    }

    private func cancel() {
        active = false
        hideOverlay()
    }

    // MARK: Window list (front-to-back z-order via CGWindowList)

    private func orderedWindows() -> [WindowInfo] {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [WindowInfo] = []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let num = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let owner = w[kCGWindowOwnerName as String] as? String else { continue }
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let width = b["Width"] ?? 0, height = b["Height"] ?? 0
            guard width > 90, height > 90 else { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            result.append(WindowInfo(
                id: num, title: title.isEmpty ? owner : title, appName: owner,
                bundleID: nil, pid: pid,
                frame: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: height),
                thumbnail: nil))
        }
        return result
    }

    private func captureThumbnails() {
        let ids = model.windows.map(\.id)
        Task {
            for (i, id) in ids.enumerated() {
                guard active else { break }
                if let img = WindowService.shared.captureWindow(windowID: id, maxDimension: 480),
                   model.windows.indices.contains(i), model.windows[i].id == id {
                    model.windows[i].thumbnail = img
                }
                await Task.yield()
            }
        }
    }

    // MARK: Overlay panel

    private func showOverlay() {
        if overlay == nil { makeOverlay() }
        DispatchQueue.main.async { [weak self] in
            guard let self, let overlay = self.overlay, let screen = NSScreen.main else { return }
            overlay.layoutIfNeeded()
            let size = overlay.contentView?.fittingSize ?? NSSize(width: 600, height: 220)
            let vf = screen.visibleFrame
            overlay.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                                    width: size.width, height: size.height), display: true)
            overlay.orderFrontRegardless()
        }
    }

    private func hideOverlay() { overlay?.orderOut(nil) }

    private func makeOverlay() {
        let host = NSHostingView(rootView: AltTabOverlayView(model: model))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 220),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        overlay = p
    }
}
