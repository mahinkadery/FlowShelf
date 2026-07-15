import AppKit
import SwiftUI

/// The iOS-style sound-output picker: a small dark glass panel that slides out
/// beside the notch (like the iPhone player's speaker sheet), listing output
/// devices with icons and a selection dot. Lives in its own borderless panel so
/// it can extend past the notch window and animate independently.
@MainActor
final class OutputPickerController {
    static let shared = OutputPickerController()
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    private let width: CGFloat = 250
    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(near anchor: NSRect) {
        isVisible ? hide() : show(near: anchor)
    }

    func show(near anchor: NSRect) {
        AudioOutputManager.shared.refresh()
        AudioOutputManager.shared.pickerOpen = true

        let host = NSHostingView(rootView: OutputPickerView())
        let size = host.fittingSize
        let p = self.panel ?? {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .statusBar
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            // Force dark so the glass materials resolve to Apple's Control-Centre
            // black, never a light-mode grey.
            p.appearance = NSAppearance(named: .darkAqua)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            return p
        }()
        p.contentView = host
        panel = p

        // Place beside the notch: to the right of the anchor (the airplay
        // button), top-aligned with it; clamped to the screen edge.
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        var x = anchor.maxX + 16
        var y = anchor.maxY - size.height + 4
        if let scr = screen {
            if x + size.width > scr.visibleFrame.maxX - 8 {
                x = anchor.minX - size.width - 16      // no room right → open left
            }
            y = min(max(y, scr.visibleFrame.minY + 8), scr.frame.maxY - size.height - 8)
        }
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)

        // Control-Centre pop: grow + fade out of the corner nearest the button
        // (a scale, not a slide — NSWindow frame animation reads as scale).
        let opensRight = target.minX > anchor.midX
        let scale: CGFloat = 0.86
        let from = NSRect(
            x: opensRight ? target.minX : target.maxX - target.width * scale,
            y: target.maxY - target.height * scale,   // grow downward from the top
            width: target.width * scale,
            height: target.height * scale)
        p.setFrame(FlowMotion.reduceMotion ? target : from, display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = FlowMotion.reduceMotion ? 0.15 : 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
            p.animator().alphaValue = 1
            p.animator().setFrame(target, display: true)
        }

        // Click anywhere outside → dismiss (transient, like a popover).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        // Local monitor: clicks inside FlowShelf's OWN windows (notch, shelf)
        // never reach the global monitor — dismiss for those too.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.window !== self?.panel { self?.hide() }
                }
                return event
            }
    }

    func hide() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        localClickMonitor = nil
        AudioOutputManager.shared.pickerOpen = false
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
}

/// Panel content: dark iOS-style device sheet — header, then device rows with an
/// SF-Symbol icon, name, and a white selection dot on the active output.
struct OutputPickerView: View {
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Sound Output")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 18)
                .padding(.top, 14)

            VStack(spacing: 3) {
                ForEach(audio.devices) { device in
                    OutputRow(device: device, selected: device.id == audio.currentID) {
                        audio.select(device.id)
                        Haptics.copy()
                    }
                }
            }
            .padding(.horizontal, 10)

            // Volume of the selected device (Control-Centre style). Devices with
            // no volume control (dock/HDMI sinks) say so instead of lying.
            // CONSTANT height — the panel window can't resize after opening, so
            // slider ↔ text swaps must not change the content's size.
            Group {
                if audio.volume != nil {
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Slider(value: Binding(get: { Double(audio.volume ?? 0) },
                                              set: { audio.setVolume(Float($0)) }), in: 0...1)
                            .controlSize(.small)
                            .tint(.white)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                } else {
                    Text("Volume is controlled on the device")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 26)
            .padding(.horizontal, 18)
            .padding(.top, 5)
            .padding(.bottom, 12)
        }
        .frame(width: 260)
        // Control-Centre recipe: Apple's official Liquid Glass (macOS 26 SwiftUI
        // .glassEffect), deepened toward black. Solid under Reduce Transparency.
        .liquidGlassSurface(cornerRadius: 22, tint: .black.opacity(0.35))
        .environment(\.colorScheme, .dark)
    }
}

private struct OutputRow: View {
    let device: AudioOutputDevice
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: device.icon)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 26)
                Text(device.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                // Control-Centre selection dot: dim disc → white disc + check.
                ZStack {
                    Circle().fill(.white.opacity(selected ? 1 : (hovering ? 0.26 : 0.14)))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(selected ? 0.13 : (hovering ? 0.07 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(FlowMotion.hover, value: hovering)
    }
}
