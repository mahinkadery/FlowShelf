import AppKit
import QuartzCore

enum DockGenieGeometry {
    static func frame(slice: CGRect, content: CGRect, icon: CGRect,
                      edge: DockPosition, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        let vertical = edge != .left && edge != .right
        let distance: CGFloat
        switch edge {
        case .left: distance = (slice.midX - content.minX) / content.width
        case .right: distance = (content.maxX - slice.midX) / content.width
        case .top: distance = (content.maxY - slice.midY) / content.height
        case .bottom, .unknown: distance = (slice.midY - content.minY) / content.height
        }
        let spread = smooth(min(max(progress * 1.5 - (1 - distance) * 0.5, 0), 1))
        let travel = smooth(progress)
        let width = vertical
            ? icon.width * 0.35 + (slice.width - icon.width * 0.35) * spread
            : slice.width * max(travel, 0.001)
        let height = vertical
            ? slice.height * max(travel, 0.001)
            : icon.height * 0.35 + (slice.height - icon.height * 0.35) * spread
        let centerX = icon.midX + (slice.midX - icon.midX) * (vertical ? spread : travel)
        let centerY = icon.midY + (slice.midY - icon.midY) * (vertical ? travel : spread)
        return CGRect(x: centerX - width / 2, y: centerY - height / 2,
                      width: width, height: height)
    }

    private static func smooth(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}

@MainActor
final class DockGenieTransition {
    private var overlay: NSPanel?
    private var generation = UUID()
    var isAnimating: Bool { overlay != nil }

    func cancel() {
        generation = UUID()
        overlay?.contentView?.layer?.removeAllAnimations()
        overlay?.orderOut(nil)
        overlay = nil
    }

    @discardableResult
    func animate(panel: NSPanel, image: CGImage?, icon: CGRect, edge: DockPosition,
                 appearing: Bool, completion: @escaping () -> Void) -> Bool {
        cancel()
        guard !FlowMotion.reduceMotion, !icon.isEmpty, let image else { return false }

        let token = UUID()
        generation = token
        let canvas = panel.frame.union(icon).insetBy(dx: -2, dy: -2)
        let content = panel.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        let target = icon.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        let surface = NSView(frame: NSRect(origin: .zero, size: canvas.size))
        surface.wantsLayer = true
        guard let root = surface.layer else { return false }
        let window = NSPanel(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.level = panel.level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = surface
        overlay = window

        let vertical = edge != .left && edge != .right
        let count = 64
        let samples = 30
        let duration = appearing ? 0.28 : 0.16
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<count {
            let fraction = CGFloat(index) / CGFloat(count)
            let next = CGFloat(index + 1) / CGFloat(count)
            let slice: CGRect
            let crop: CGRect
            if vertical {
                slice = CGRect(x: content.minX, y: content.minY + content.height * fraction,
                               width: content.width, height: content.height / CGFloat(count))
                let low = floor(CGFloat(image.height) * (1 - next))
                let high = ceil(CGFloat(image.height) * (1 - fraction))
                crop = CGRect(x: 0, y: low, width: CGFloat(image.width), height: high - low)
            } else {
                slice = CGRect(x: content.minX + content.width * fraction, y: content.minY,
                               width: content.width / CGFloat(count), height: content.height)
                let low = floor(CGFloat(image.width) * fraction)
                let high = ceil(CGFloat(image.width) * next)
                crop = CGRect(x: low, y: 0, width: high - low, height: CGFloat(image.height))
            }
            let layer = CALayer()
            layer.contents = image.cropping(to: crop)
            layer.contentsGravity = .resize
            layer.contentsScale = panel.backingScaleFactor
            root.addSublayer(layer)
            let frames = (0...samples).map { sample -> CGRect in
                let time = CGFloat(sample) / CGFloat(samples)
                return DockGenieGeometry.frame(slice: slice, content: content, icon: target,
                                               edge: edge, progress: appearing ? time : 1 - time)
            }
            let end = frames.last!
            layer.bounds = CGRect(origin: .zero, size: end.size)
            layer.position = CGPoint(x: end.midX, y: end.midY)
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = frames.map { NSValue(point: CGPoint(x: $0.midX, y: $0.midY)) }
            let bounds = CAKeyframeAnimation(keyPath: "bounds")
            bounds.values = frames.map {
                NSValue(rect: CGRect(x: 0, y: 0, width: $0.width + (vertical ? 0 : 0.5),
                                    height: $0.height + (vertical ? 0.5 : 0)))
            }
            let group = CAAnimationGroup()
            group.animations = [position, bounds]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(group, forKey: "genie")
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = appearing ? [0, 1, 1] : [1, 1, 0]
        fade.keyTimes = appearing ? [0, 0.18, 1] : [0, 0.65, 1]
        fade.duration = duration
        root.add(fade, forKey: "visibility")
        CATransaction.commit()
        panel.alphaValue = 0
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == token else { return }
            completion()
            self.cancel()
        }
        return true
    }
}
