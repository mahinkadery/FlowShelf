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

    func load(pid: pid_t, appName: String, icon: NSImage?, bundleID: String?) {
        self.appName = appName
        self.icon = icon
        self.windows = []
        self.loading = true
        let token = UUID(); loadToken = token
        Task {
            let result = await WindowService.shared.loadWindows(
                pid: pid, appName: appName, bundleID: bundleID, thumbnails: true)
            guard token == loadToken else { return }
            self.windows = result
            self.loading = false
        }
    }
}

/// The glass preview card shown above a hovered Dock icon.
struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel
    var onActivate: (WindowInfo) -> Void
    var onClose: (WindowInfo) -> Void
    var onMinimize: (WindowInfo) -> Void

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
                HStack(spacing: 7) { ProgressView().controlSize(.small)
                    Text("Capturing…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .frame(height: thumbH).frame(maxWidth: .infinity)
            } else if model.windows.isEmpty {
                Text("No open windows")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: thumbH).frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.windows) { w in
                            WindowThumb(window: w, appIcon: model.icon,
                                        width: thumbW, height: thumbH,
                                        onActivate: { onActivate(w) },
                                        onClose: { onClose(w) },
                                        onMinimize: { onMinimize(w) })
                        }
                    }
                    .padding(.bottom, 2)
                }

                if !model.loading && model.windows.allSatisfy({ $0.thumbnail == nil }) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 10))
                        Text("Can’t capture previews — enable Screen Recording for FlowShelf, then quit & reopen.")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 1040)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private let thumbW: CGFloat = 300
    private let thumbH: CGFloat = 188
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
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                                  lineWidth: hovering ? 2 : 1))

                if hovering {
                    HStack(spacing: 5) {
                        circleButton("minus") { onMinimize() }
                        circleButton("xmark") { onClose() }
                    }.padding(6)
                }
            }
            Text(window.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onActivate() }
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
    private let gap: CGFloat = 10

    var isVisible: Bool { panel?.isVisible ?? false }

    var containsMouse: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    func present(pid: pid_t, appName: String, icon: NSImage?, bundleID: String?,
                 iconFrameCG: CGRect, dockPosition: DockPosition) {
        if panel == nil { makePanel() }
        // Same app already shown — just refresh content, keep position.
        if currentPID != pid {
            currentPID = pid
            model.load(pid: pid, appName: appName, icon: icon, bundleID: bundleID)
        }

        // Let SwiftUI size itself, then anchor to the icon.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            panel.layoutIfNeeded()
            let fitting = panel.contentView?.fittingSize ?? NSSize(width: 420, height: 260)
            let w = min(max(fitting.width, 260), 1040)
            let h = min(max(fitting.height, 240), 520)
            let origin = self.anchorOrigin(iconFrameCG: iconFrameCG, panel: NSSize(width: w, height: h),
                                           dockPosition: dockPosition)
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        currentPID = nil
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
        if let vf = screen?.visibleFrame {
            x = min(max(x, vf.minX + 6), vf.maxX - size.width - 6)
            y = min(max(y, vf.minY + 6), vf.maxY - size.height - 6)
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
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        panel = p
    }
}
