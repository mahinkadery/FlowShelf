import AppKit
import SwiftUI

/// A Dynamic-Island-style shelf at the top of **every** screen: the built-in
/// display uses its real notch; external monitors get a matching top-centre pill.
/// Each screen has its own independent shelf. Opens on a deliberate **downward
/// swipe** out of the notch/pill (not on hover); the window never resizes — the
/// card morphs.
@MainActor
final class NotchController {
    static let shared = NotchController()

    private final class Unit {
        let screen: NSScreen
        let panel: NSPanel
        let model: NotchModel
        var lastDistFromTop: CGFloat = .greatestFiniteMagnitude
        var collapseWork: DispatchWorkItem?
        init(screen: NSScreen, panel: NSPanel, model: NotchModel) {
            self.screen = screen; self.panel = panel; self.model = model
        }
    }

    private var units: [Unit] = []
    private var screenObserver: NSObjectProtocol?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private(set) var running = false

    private let sideMargin: CGFloat = 60
    private let bottomMargin: CGFloat = 40

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        rebuild()
        startMouseMonitor()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
    }

    func stop() {
        running = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        stopMouseMonitor()
        teardown()
    }

    private func teardown() {
        for u in units { u.collapseWork?.cancel(); u.panel.orderOut(nil) }
        units.removeAll()
    }

    /// One shelf panel per screen.
    private func rebuild() {
        teardown()
        for screen in NSScreen.screens {
            let model = NotchModel()
            model.collapsedSize = notchSize(on: screen)
            // On the real notch the collapsed area is dead hardware space, so it's
            // safe to make it a drag/hover target. On external screens it would sit
            // over the menu bar, so keep the collapsed pill click-through (it still
            // opens via the downward swipe).
            let hasNotch = screen.safeAreaInsets.top > 0
            let panel = makePanel(model: model, interactiveCollapsed: hasNotch)
            let unit = Unit(screen: screen, panel: panel, model: model)
            position(unit)
            panel.orderFrontRegardless()
            units.append(unit)
        }
    }

    // MARK: - Geometry

    /// Physical notch size on the built-in display; a synthetic top-centre pill on
    /// notchless / external displays.
    private func notchSize(on screen: NSScreen) -> CGSize {
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: max(screen.frame.width - left.width - right.width, 120),
                          height: max(inset, 24))
        }
        return CGSize(width: 200, height: 32)
    }

    private func notchRect(_ unit: Unit) -> CGRect {
        let s = unit.model.collapsedSize
        return CGRect(x: unit.screen.frame.midX - s.width / 2,
                      y: unit.screen.frame.maxY - s.height, width: s.width, height: s.height)
    }

    private func expandedRect(_ unit: Unit) -> CGRect {
        let s = unit.model.expandedSize
        return CGRect(x: unit.screen.frame.midX - s.width / 2,
                      y: unit.screen.frame.maxY - s.height, width: s.width, height: s.height)
    }

    private func makePanel(model: NotchModel, interactiveCollapsed: Bool) -> NSPanel {
        let host = NotchHostingView(rootView: NotchView(model: model))
        host.sizingOptions = []
        host.regionSize = { [weak model] in
            guard let model else { return .zero }
            if model.expanded { return model.expandedSize }
            return interactiveCollapsed ? model.collapsedSize : .zero
        }
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        return p
    }

    private func position(_ unit: Unit) {
        let scr = unit.screen
        let winW = unit.model.expandedSize.width + sideMargin * 2
        let winH = unit.model.expandedSize.height + bottomMargin
        unit.panel.setFrame(CGRect(x: scr.frame.midX - winW / 2,
                                   y: scr.frame.maxY - winH,
                                   width: winW, height: winH), display: true)
    }

    // MARK: - Swipe-aware open/close

    private func startMouseMonitor() {
        // NSEvent monitors are delivered on the main thread, so run synchronously
        // there instead of spawning a Task per mouse-move (this fires ~100×/sec).
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { ev in handler(ev); return ev }
    }

    private func stopMouseMonitor() {
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal) }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal) }
        mouseGlobal = nil; mouseLocal = nil
    }

    private func handleMouse() {
        guard running else { return }
        let mouse = NSEvent.mouseLocation
        for unit in units {
            let scr = unit.screen
            guard scr.frame.contains(mouse) else {
                if unit.model.expanded { scheduleCollapse(unit) }
                unit.lastDistFromTop = .greatestFiniteMagnitude
                continue
            }
            let distFromTop = scr.frame.maxY - mouse.y
            let notch = notchRect(unit)
            let notchH = notch.height
            let inX = mouse.x >= notch.minX - 10 && mouse.x <= notch.maxX + 10

            if unit.model.expanded {
                if expandedRect(unit).insetBy(dx: -12, dy: -12).contains(mouse) {
                    unit.collapseWork?.cancel()
                } else {
                    scheduleCollapse(unit)
                }
            } else {
                let movingDown = distFromTop > unit.lastDistFromTop + 0.3
                let cameFromNotch = unit.lastDistFromTop <= notchH + 2
                let nowJustBelow = distFromTop > notchH && distFromTop < notchH + 48
                if inX, movingDown, cameFromNotch, nowJustBelow {
                    unit.collapseWork?.cancel()
                    unit.model.expanded = true
                }
            }
            unit.lastDistFromTop = distFromTop
        }
    }

    /// Called by the view when a drag leaves the notch — collapse any open shelf.
    func scheduleCollapseAll() {
        for unit in units { scheduleCollapse(unit) }
    }

    private func scheduleCollapse(_ unit: Unit) {
        unit.collapseWork?.cancel()
        let work = DispatchWorkItem { [weak unit] in
            guard let unit else { return }
            if !unit.model.targeted { unit.model.expanded = false }
        }
        unit.collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// Hosting view that lets clicks pass through everywhere except the visible card.
final class NotchHostingView: NSHostingView<NotchView> {
    var regionSize: () -> CGSize = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let s = regionSize()
        guard s.width > 0, s.height > 0 else { return nil }
        let rect = NSRect(x: (bounds.width - s.width) / 2,
                          y: bounds.height - s.height,
                          width: s.width, height: s.height)
        return rect.contains(point) ? super.hitTest(point) : nil
    }
}
