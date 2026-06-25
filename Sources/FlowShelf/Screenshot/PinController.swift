import AppKit

/// Pins a screenshot to the screen as a floating, always-on-top window — drag to
/// move, scroll to resize, double-click or ⎋/right-click to dismiss (Shottr-style).
@MainActor
final class PinController {
    static let shared = PinController()
    private var panels: [NSPanel] = []
    private init() {}

    func pin(_ image: NSImage) {
        let pixels = image.pixelSize()
        // Start at a comfortable size capped to the screen, preserving aspect.
        let maxDim: CGFloat = 700
        let scale = min(1, maxDim / max(pixels.width, pixels.height, 1))
        let size = NSSize(width: max(pixels.width * scale, 80), height: max(pixels.height * scale, 60))

        let view = PinImageView(image: image)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false   // the view drives dragging
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        view.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            self?.close(panel)
        }

        // Place near the pointer, clamped to the screen.
        let mouse = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vf = scr?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(origin)

        panel.orderFrontRegardless()
        panels.append(panel)
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 == panel }
    }
}

/// The image view inside a pin: draws the shot, drags the window, scroll-resizes,
/// and dismisses on double-click / right-click / Esc.
private final class PinImageView: NSView {
    private let image: NSImage
    private let aspect: CGFloat
    var onClose: (() -> Void)?

    init(image: NSImage) {
        self.image = image
        let p = image.pixelSize()
        self.aspect = max(p.height, 1) / max(p.width, 1)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { onClose?(); return }
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }   // 53 = Esc
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let factor = 1 + (event.scrollingDeltaY * 0.004)
        var f = window.frame
        let newW = min(max(f.width * factor, 80), 2400)
        let newH = newW * aspect
        // Resize from the centre.
        f.origin.x -= (newW - f.width) / 2
        f.origin.y -= (newH - f.height) / 2
        f.size = NSSize(width: newW, height: newH)
        window.setFrame(f, display: true)
    }
}

private extension NSImage {
    func pixelSize() -> NSSize {
        if let rep = representations.first {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return size
    }
}
