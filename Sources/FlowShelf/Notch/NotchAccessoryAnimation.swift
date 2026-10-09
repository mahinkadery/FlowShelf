import SwiftUI
import AppKit
import QuartzCore
import ImageIO

enum NotchAccessoryKind: String, CaseIterable {
    case earbudsPro = "earbuds-pro"
    case headphones

    init?(symbol: String) {
        switch symbol {
        case "airpods", "airpodspro": self = .earbudsPro
        case "airpodsmax", "headphones": self = .headphones
        default: return nil
        }
    }
}

enum NotchAccessoryFrames {
    static let count = 60
    static let columns = 10
    static let rows = 6
    static let cellSize = 96
    static let duration: TimeInterval = 1

    static func rect(at index: Int) -> CGRect {
        let frame = min(count - 1, max(0, index))
        return CGRect(x: Double(frame % columns) / Double(columns),
                      y: Double(rows - 1 - frame / columns) / Double(rows),
                      width: 1 / Double(columns), height: 1 / Double(rows))
    }

    static func animation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (0..<count).map { NSValue(rect: rect(at: $0)) }
        animation.keyTimes = (0...count).map { NSNumber(value: Double($0) / Double(count)) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = 0
        animation.isRemovedOnCompletion = true
        return animation
    }
}

@MainActor
enum NotchAccessoryAssets {
    private static var cachedAtlas: (NotchAccessoryKind, CGImage)?
    private static var posters: [NotchAccessoryKind: CGImage] = [:]

    static func poster(for kind: NotchAccessoryKind) -> CGImage? {
        if let image = posters[kind] { return image }
        guard let image = load(kind, atlas: false) else { return nil }
        posters[kind] = image
        return image
    }

    static func atlas(for kind: NotchAccessoryKind) -> CGImage? {
        if let cachedAtlas, cachedAtlas.0 == kind { return cachedAtlas.1 }
        guard let image = load(kind, atlas: true) else { return nil }
        cachedAtlas = (kind, image)
        return image
    }

    private static func load(_ kind: NotchAccessoryKind, atlas: Bool) -> CGImage? {
        let suffix = atlas ? "atlas" : "still"
        guard let url = Bundle.main.url(forResource: "\(kind.rawValue)-\(suffix)",
                                        withExtension: "png", subdirectory: "Notch3D"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let width = NotchAccessoryFrames.cellSize * (atlas ? NotchAccessoryFrames.columns : 1)
        let height = NotchAccessoryFrames.cellSize * (atlas ? NotchAccessoryFrames.rows : 1)
        guard image.width == width, image.height == height else { return nil }
        return image
    }
}

struct NotchAccessoryAnimation: NSViewRepresentable {
    let kind: NotchAccessoryKind
    let playing: Bool

    func makeNSView(context: Context) -> AccessoryView {
        let view = AccessoryView()
        view.configure(kind: kind, playing: playing)
        return view
    }

    func updateNSView(_ view: AccessoryView, context: Context) {
        view.configure(kind: kind, playing: playing)
    }

    static func dismantleNSView(_ view: AccessoryView, coordinator: ()) { view.stop() }

    final class AccessoryView: NSView {
        private let sprite = CALayer()
        private var kind: NotchAccessoryKind?
        private var wantsPlayback = false
        private var played = false
        private lazy var activity = NotchViewActivity { [weak self] in self?.refresh() }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            sprite.contentsGravity = .resize
            sprite.magnificationFilter = .linear
            sprite.minificationFilter = .linear
            sprite.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(sprite)
        }

        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.frame = bounds
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activity.attach(to: self)
        }

        override func viewDidHide() { super.viewDidHide(); refresh() }
        override func viewDidUnhide() { super.viewDidUnhide(); refresh() }

        func configure(kind: NotchAccessoryKind, playing: Bool) {
            if self.kind != kind {
                sprite.removeAllAnimations()
                played = false
                self.kind = kind
            }
            wantsPlayback = playing
            refresh()
        }

        private func refresh() {
            guard let kind else { return }
            let allowed = wantsPlayback && activity.isVisible
                && !NotchPresentationState.shared.reduceMotion
                && !ProcessInfo.processInfo.isLowPowerModeEnabled
            guard allowed else {
                sprite.removeAllAnimations()
                sprite.contents = NotchAccessoryAssets.poster(for: kind)
                sprite.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                return
            }
            guard !played else { return }
            played = true
            guard let atlas = NotchAccessoryAssets.atlas(for: kind) else {
                sprite.contents = NotchAccessoryAssets.poster(for: kind)
                sprite.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                return
            }
            sprite.contents = atlas
            sprite.contentsRect = NotchAccessoryFrames.rect(at: NotchAccessoryFrames.count - 1)
            sprite.add(NotchAccessoryFrames.animation(), forKey: "accessory-turn")
        }

        func stop() {
            activity.detach()
            wantsPlayback = false
            kind = nil
            sprite.removeAllAnimations()
            sprite.contents = nil
        }
    }
}
