import AppKit
import SwiftUI

/// A Dynamic-Island-style shelf in the MacBook notch. Uses the technique the good
/// notch apps use for a buttery morph: a **fixed-size** borderless panel pinned
/// flush to the screen's top edge, click-through everywhere except the visible
/// card (via `hitTest`), and the collapse/expand handled entirely by animating the
/// SwiftUI card — the window itself never resizes (that's what kills the jank).
@MainActor
final class NotchController {
    static let shared = NotchController()

    private var panel: NSPanel?
    private let model = NotchModel()
    private var screenObserver: NSObjectProtocol?
    private(set) var running = false

    private let sideMargin: CGFloat = 60      // room for the expanded card + shadow
    private let bottomMargin: CGFloat = 40

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        buildPanel()
        layout()
        panel?.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.layout() }
            }
        running = true
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        model.expanded = false
        panel?.orderOut(nil)
        panel = nil
        running = false
    }

    // MARK: - Geometry

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// The physical notch size (or a sensible top-center pill on notchless Macs).
    private func notchSize(on screen: NSScreen) -> CGSize {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return CGSize(width: max(screen.frame.width - left.width - right.width, 120),
                          height: max(inset, 24))
        }
        return CGSize(width: 200, height: 32)
    }

    // MARK: - Panel

    private func buildPanel() {
        let host = NotchHostingView(rootView: NotchView(model: model))
        host.sizingOptions = []
        // Click-through everywhere except the current card region (top-centre).
        host.regionSize = { [weak self] in
            guard let self else { return .zero }
            return self.model.expanded ? self.model.expandedSize : self.model.collapsedSize
        }
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))   // above the menu bar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        panel = p
    }

    /// Fixed window: wide/tall enough for the expanded card + shadow, centred on
    /// the notch, with its top edge flush against the screen's physical top.
    private func layout() {
        guard let panel, let scr = notchScreen() else { return }
        model.collapsedSize = notchSize(on: scr)
        let winW = model.expandedSize.width + sideMargin * 2
        let winH = model.expandedSize.height + bottomMargin
        let frame = CGRect(x: scr.frame.midX - winW / 2,
                           y: scr.frame.maxY - winH,   // top edge at the screen top
                           width: winW, height: winH)
        panel.setFrame(frame, display: true)
    }
}

/// Hosting view that lets clicks pass through everywhere except the visible card
/// (a top-centred rect of the current collapsed/expanded size).
final class NotchHostingView: NSHostingView<NotchView> {
    var regionSize: () -> CGSize = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let s = regionSize()
        guard s.width > 0, s.height > 0 else { return nil }
        let rect = NSRect(x: (bounds.width - s.width) / 2,
                          y: bounds.height - s.height,   // top-anchored (AppKit y-up)
                          width: s.width, height: s.height)
        return rect.contains(point) ? super.hitTest(point) : nil
    }
}
