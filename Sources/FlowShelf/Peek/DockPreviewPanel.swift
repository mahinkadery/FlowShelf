import SwiftUI
import AppKit

/// Backing model for a Dock-hover preview: holds the app's windows + loads
/// thumbnails on demand.
@MainActor
final class DockPreviewModel: ObservableObject {
    @Published var appName: String = ""
    @Published var icon: NSImage?
    @Published var windows: [WindowInfo] = []
    @Published var loading = false

    private var loadToken = UUID()
    private var loadTask: Task<Void, Never>?
    var onLoaded: (() -> Void)?
    var scrollOffset: CGFloat = 0

    func cancel() {
        loadToken = UUID()
        loadTask?.cancel()
        loadTask = nil
        windows = []
        loading = false
    }

    func load(pid: pid_t, appName: String, icon: NSImage?, bundleID: String?) {
        self.appName = appName
        self.icon = icon
        self.windows = []
        self.loading = true
        scrollOffset = 0
        let token = UUID(); loadToken = token
        loadTask?.cancel()
        loadTask = Task {
            guard !Task.isCancelled else { return }
            let result = await WindowService.shared.loadWindows(
                pid: pid, appName: appName, bundleID: bundleID, thumbnails: true)
            guard !Task.isCancelled, token == loadToken else { return }
            withAnimation(FlowMotion.listChange) {
                self.windows = result
                self.loading = false
            }
            self.onLoaded?()
        }
    }
}

/// The glass preview card shown above a hovered Dock icon.
struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel
    var onActivate: (WindowInfo) -> Void
    var onClose: (WindowInfo) -> Void
    var onMinimize: (WindowInfo) -> Void
    var rendersForTransition = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                Text(model.appName).font(.system(size: 13, weight: .semibold))
                Text("\(model.windows.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
            }

            if model.loading && model.windows.isEmpty {
                HStack(spacing: 7) {
                    if rendersForTransition {
                        Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Capturing…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .frame(height: thumbH).frame(maxWidth: .infinity)
            } else if model.windows.isEmpty {
                Text(PrivateWindowSymbols.shared.supportsWindowIDs ? "No open windows"
                     : "Window listing is unavailable on this macOS version")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: thumbH).frame(maxWidth: .infinity)
            } else {
                if rendersForTransition {
                    windowStrip
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: -model.scrollOffset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        windowStrip
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: DockPreviewScrollOffset.self,
                                    value: geometry.frame(in: .named("peekViewport")).minX)
                            })
                    }
                    .coordinateSpace(name: "peekViewport")
                    .onPreferenceChange(DockPreviewScrollOffset.self) { model.scrollOffset = max(0, -$0) }
                }

                if !model.loading && model.windows.allSatisfy({ $0.thumbnail == nil }) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 10))
                        Text(PrivateWindowSymbols.shared.supportsCapture
                             ? "Can’t capture previews — enable Screen Recording for FlowShelf, then quit & reopen."
                             : "Window previews are unavailable on this macOS version.")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 1040)
        .modifier(DockPreviewSurface(rasterized: rendersForTransition))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient(
                colors: [.white.opacity(0.30), .white.opacity(0.06), .white.opacity(0.12)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private var thumbW: CGFloat { AppSettings.shared.dockPreviewSize.thumb.width }
    private var thumbH: CGFloat { AppSettings.shared.dockPreviewSize.thumb.height }

    private var windowStrip: some View {
        HStack(spacing: 12) {
            ForEach(model.windows) { window in
                WindowThumb(window: window, appIcon: model.icon,
                            width: thumbW, height: thumbH,
                            onActivate: { onActivate(window) },
                            onClose: { onClose(window) },
                            onMinimize: { onMinimize(window) })
                    .transition(FlowMotion.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.bottom, 2)
        .animation(rendersForTransition ? nil : FlowMotion.listChange, value: model.windows)
    }
}

private struct DockPreviewScrollOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DockPreviewSurface: ViewModifier {
    var rasterized: Bool

    func body(content: Content) -> some View {
        if rasterized {
            content.background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            content.liquidGlassSurface(cornerRadius: 20, tint: .black.opacity(0.42))
        }
    }
}

private struct WindowThumb: View {
    let window: WindowInfo
    let appIcon: NSImage?
    let width: CGFloat
    let height: CGFloat
    var onActivate: () -> Void
    var onClose: () -> Void
    var onMinimize: () -> Void
    @State private var hovering = false

    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let t = window.thumbnail {
                        Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
                .frame(width: width, height: height)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // Glass sheen along the top, brighter on hover.
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(hovering ? 0.10 : 0.04), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.75) : .white.opacity(0.10),
                                  lineWidth: hovering ? 1.5 : 1))

                if hovering {
                    HStack(spacing: 5) {
                        circleButton("minus") { onMinimize() }
                        circleButton("xmark") { onClose() }
                    }
                    .padding(6)
                    .transition(FlowMotion.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6, anchor: .topTrailing)))
                }
            }
            Text(window.title.isEmpty ? "Untitled window" : window.title)
                .font(.system(size: 11, weight: hovering ? .medium : .regular))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .scaleEffect(FlowMotion.reduceMotion ? 1 : pressing ? 0.96 : (hovering ? 1.035 : 1.0))
        .offset(y: !FlowMotion.reduceMotion && hovering && !pressing ? -2 : 0)
        .shadow(color: .black.opacity(hovering ? 0.4 : 0), radius: hovering ? 9 : 0, y: 4)
        .zIndex(hovering ? 1 : 0)
        .animation(FlowMotion.hoverScale, value: hovering)
        .animation(FlowMotion.press, value: pressing)
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false; onActivate() }
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48).opacity(0.55)
                } else {
                    Image(systemName: "macwindow").font(.system(size: 26)).foregroundStyle(.tertiary)
                }
            }
    }

    private func circleButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Owns the floating preview NSPanel and positions it next to the hovered icon,
/// honoring the Dock's actual position (bottom/left/right/top).
@MainActor
final class DockPreviewController {
    private var panel: NSPanel?
    private let model = DockPreviewModel()
    private var currentPID: pid_t?
    private var hiding = false
    private var presentationToken = UUID()
    private var iconFrameCG: CGRect = .zero
    private var dockPosition: DockPosition = .bottom
    private let genie = DockGenieTransition()
    private let gap: CGFloat = 0

    var isVisible: Bool { (panel?.isVisible ?? false) && !hiding }

    var containsMouse: Bool {
        guard let panel, isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    func keepsOpen(at point: CGPoint, currentIconFrameCG: CGRect?) -> Bool {
        guard let panel, isVisible else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? iconFrameCG.maxY
        let currentIcon = currentIconFrameCG.map {
            CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height)
        } ?? iconFrameCocoa
        return DockPreviewHoverRegion.contains(point, icon: iconFrameCocoa.union(currentIcon),
                                              panel: panel.frame, edge: dockPosition)
    }

    func present(pid: pid_t, appName: String, icon: NSImage?, bundleID: String?,
                 iconFrameCG: CGRect, dockPosition: DockPosition) {
        if panel == nil { makePanel() }
        let token = UUID()
        presentationToken = token
        genie.cancel()
        hiding = false
        self.iconFrameCG = iconFrameCG
        self.dockPosition = dockPosition
        // Same app already shown — just refresh content, keep position.
        if currentPID != pid {
            currentPID = pid
            model.load(pid: pid, appName: appName, icon: icon, bundleID: bundleID)
        }

        // Let SwiftUI size itself, then anchor to the icon.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel,
                  self.presentationToken == token, !self.hiding else { return }
            let wasVisible = panel.isVisible
            self.layoutPanel()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            if wasVisible || !self.genie.animate(panel: panel, image: self.transitionImage(), icon: self.iconFrameCocoa,
                                                edge: dockPosition, appearing: true, completion: { [weak self] in
                guard let self, self.presentationToken == token, !self.hiding else { return }
                self.layoutPanel()
                panel.alphaValue = 1
            }) {
                panel.alphaValue = 1
            }
        }
    }

    func hide(animated: Bool = true) {
        if hiding && animated { return }
        presentationToken = UUID()
        let token = presentationToken
        currentPID = nil
        let interrupted = genie.isAnimating
        genie.cancel()
        guard let panel, panel.isVisible else {
            model.cancel()
            return
        }
        hiding = true
        let finish = { [weak self] in
            guard let self, self.presentationToken == token else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            self.hiding = false
        }
        let animating = animated && !interrupted && genie.animate(
            panel: panel, image: transitionImage(), icon: iconFrameCocoa, edge: dockPosition, appearing: false, completion: finish)
        model.cancel()
        if !animating { finish() }
    }

    private var iconFrameCocoa: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? iconFrameCG.maxY
        return CGRect(x: iconFrameCG.minX, y: primaryHeight - iconFrameCG.maxY,
                      width: iconFrameCG.width, height: iconFrameCG.height)
    }

    private func transitionImage() -> CGImage? {
        guard !FlowMotion.reduceMotion, let panel else { return nil }
        let dark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = DockPreviewView(model: model, onActivate: { _ in }, onClose: { _ in },
                                   onMinimize: { _ in }, rendersForTransition: true)
            .frame(width: panel.frame.width, height: panel.frame.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = panel.backingScaleFactor
        return renderer.cgImage
    }

    private func layoutPanel() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(iconFrameCocoa) } ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let thumb = AppSettings.shared.dockPreviewSize.thumb
        let count = CGFloat(max(1, min(model.windows.count, 3)))
        let width = min(thumb.width * count + (count - 1) * 12 + 32, 1040, available.width - 12)
        let height = min(thumb.height + 104, available.height - 12)
        let size = NSSize(width: width, height: height)
        panel.setFrame(NSRect(origin: anchorOrigin(iconFrameCG: iconFrameCG, panel: size,
                                                  dockPosition: dockPosition), size: size), display: true)
        panel.layoutIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    /// Convert the icon's CoreGraphics (top-left) frame to a Cocoa origin for the
    /// panel, placed on the correct side of the Dock.
    private func anchorOrigin(iconFrameCG: CGRect, panel size: NSSize,
                              dockPosition: DockPosition) -> NSPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? iconFrameCG.maxY
        // Icon rect in Cocoa (bottom-left) coordinates.
        let iconCocoa = NSRect(x: iconFrameCG.minX,
                               y: primaryH - iconFrameCG.maxY,
                               width: iconFrameCG.width,
                               height: iconFrameCG.height)

        var x: CGFloat
        var y: CGFloat
        switch dockPosition {
        case .left:
            x = iconCocoa.maxX + gap
            y = iconCocoa.midY - size.height / 2
        case .right:
            x = iconCocoa.minX - size.width - gap
            y = iconCocoa.midY - size.height / 2
        case .top:
            x = iconCocoa.midX - size.width / 2
            y = iconCocoa.minY - size.height - gap
        case .bottom, .unknown:
            x = iconCocoa.midX - size.width / 2
            y = iconCocoa.maxY + gap            // above the icon
        }

        // Clamp to the screen the icon sits on.
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: iconCocoa.midX, y: iconCocoa.midY)) }
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let full = screen.frame
            switch dockPosition {
            case .left, .right:
                x = min(max(x, full.minX), full.maxX - size.width)
                y = min(max(y, visible.minY + 6), visible.maxY - size.height - 6)
            case .bottom, .top, .unknown:
                x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
                y = min(max(y, full.minY), full.maxY - size.height)
            }
        }
        return NSPoint(x: x, y: y)
    }

    private func makePanel() {
        let view = DockPreviewView(
            model: model,
            onActivate: { [weak self] w in AX.raiseWindow(pid: w.pid, windowID: w.id); self?.hide() },
            onClose: { w in AX.closeWindow(pid: w.pid, windowID: w.id) },
            onMinimize: { w in AX.minimizeWindow(pid: w.pid, windowID: w.id) })
        let host = NSHostingView(rootView: view)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.animationBehavior = .none        // we drive appear/dismiss ourselves
        p.contentView = host
        panel = p
        model.onLoaded = { [weak self] in
            guard let self, self.isVisible, !self.genie.isAnimating else { return }
            self.layoutPanel()
        }
    }
}
