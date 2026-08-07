import SwiftUI
import AppKit

@MainActor
final class PeekViewModel: ObservableObject {
    @Published var apps: [AppWindows] = []
    @Published var loading = false          // first load only — content stays put on later refreshes
    @Published var refreshing = false       // any in-flight capture (spins the refresh button)
    @Published var live = false             // auto-refresh heartbeat is running
    /// Ground-truth: nil = not yet checked, true/false = actual capture result.
    @Published var captureWorks: Bool?

    private var generation = 0              // stale-result guard
    private var heartbeat: Timer?

    /// Capture all windows. Existing tiles stay on screen while the new set is
    /// captured — no blank-out, no flicker; results from superseded refreshes
    /// are dropped so rapid clicks can't land out of order.
    func refresh() {
        captureWorks = WindowService.shared.canCaptureNow()
        generation += 1
        let gen = generation
        if apps.isEmpty { loading = true }
        refreshing = true
        Task {
            let result = await WindowService.shared.allAppWindows(thumbnails: true)
            guard gen == self.generation else { return }   // a newer refresh superseded us
            withAnimation(FlowMotion.listChange) { self.apps = result }
            self.loading = false
            self.refreshing = false
        }
    }

    /// Gentle auto-refresh while the pane is visible, so previews stay current
    /// without hammering the capture pipeline.
    func startHeartbeat() {
        stopHeartbeat()
        guard captureWorks != false else { return }
        live = true
        heartbeat = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            Task { @MainActor in
                guard !self.refreshing else { return }     // never stack captures
                self.refresh()
            }
        }
    }

    func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
        live = false
    }

    /// Release captured thumbnails from memory when the tab isn't visible.
    func clear() {
        stopHeartbeat()
        generation += 1        // orphan any in-flight capture
        apps = []
        refreshing = false
    }
}

/// The "Peek" dashboard tab: every app with open windows, live thumbnails,
/// click to switch. Always works (given Screen Recording) regardless of the
/// Dock-hover detection.
struct PeekView: View {
    @StateObject private var model = PeekViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var refreshTick = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !Permissions.hasAccessibility {
                permissionBanner(
                    "Accessibility required",
                    "Peek needs this to list each app’s windows and switch to them. ① Open FlowShelf.app first from your Applications folder (not the disk image). ② Turn FlowShelf ON in the list. ③ Quit & Reopen — the grant only applies on the next launch.",
                    pane: .accessibility,
                    showRelaunch: true)
            }
            // Drive this banner off an ACTUAL capture attempt, not the unreliable
            // CGPreflightScreenCaptureAccess flag.
            if Permissions.hasAccessibility && model.captureWorks == false {
                permissionBanner(
                    "Turn on Screen Recording, then Quit & Reopen",
                    "① Make sure you’re running FlowShelf from your Applications folder — not the disk image or Downloads (that’s the usual cause). ② Turn FlowShelf ON under Screen Recording. ③ Quit & Reopen — the grant only applies on the next launch. Only if it still won’t capture, remove FlowShelf with “–”, then restart your Mac and turn it on again (removing without a restart can stop the prompt from reappearing).",
                    pane: .screenRecording,
                    showRelaunch: true)
            }
            content
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings — re-check so a fresh grant shows
            // immediately instead of waiting for a manual refresh.
            model.refresh()
        }
        .onAppear { model.refresh(); model.startHeartbeat() }
        .onDisappear { model.clear() }
    }

    // Toolbar only — the pane title lives in the big PaneHeader above.
    private var header: some View {
        HStack(spacing: 10) {
            if let works = model.captureWorks {
                HStack(spacing: 6) {
                    if works && model.live {
                        PulseDot()
                        Text("Live previews")
                    } else {
                        Image(systemName: works ? "checkmark.circle.fill" : "xmark.circle")
                        Text(works ? "Capture working" : "No capture")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(works ? .green : .orange)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill((works ? Color.green : Color.orange).opacity(0.12)))
                .help(works ? "Window previews refresh automatically while this tab is open."
                      : "FlowShelf can't capture yet — see the banner below.")
            }
            Spacer()
            Toggle(isOn: $settings.dockPreviewsEnabled) {
                Text("Dock hover previews").font(.system(size: 11.5))
            }
            .toggleStyle(.switch).controlSize(.small)
            .onChange(of: settings.dockPreviewsEnabled) { _, on in
                if on { DockPreviewsCoordinator.enable() } else { DockObserver.shared.stop() }
            }
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.refreshing ? 360 : 0))
                    .animation(model.refreshing
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                               : .default,
                               value: model.refreshing)
            }.help("Refresh now")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if model.loading && model.apps.isEmpty {
            VStack { Spacer(); ProgressView("Capturing windows…").controlSize(.small); Spacer() }
                .frame(maxWidth: .infinity)
        } else if model.apps.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                GlassCircleBadge(icon: "macwindow.on.rectangle")
                Text(Permissions.hasAccessibility ? "No open windows found"
                     : "Grant Accessibility above to see open windows")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.apps) { app in
                        appSection(app)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .animation(FlowMotion.listChange, value: model.apps.map(\.id))
            }
        }
    }

    private func appSection(_ app: AppWindows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                Text(app.appName).font(.system(size: 13, weight: .semibold))
                Text("\(app.windows.count)")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentTransition(.numericText())
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(app.windows) { w in
                    PeekTile(window: w)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .animation(FlowMotion.listChange, value: app.windows)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedCard()
    }

    private func permissionBanner(_ title: String, _ detail: String, pane: Permissions.Pane,
                                  showRelaunch: Bool = false) -> some View {
        HStack(spacing: 11) {
            EmblemChip(icon: "exclamationmark.shield.fill", tint: .orange)
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            VStack(spacing: 4) {
                Button("Open Settings") {
                    if pane == .accessibility { Permissions.requestAccessibility() }
                    else { Permissions.requestScreenRecording() }
                    Permissions.openSettings(pane)
                }.controlSize(.small)
                if showRelaunch {
                    Button("Quit & Reopen") { AppRelaunch.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color.orange.opacity(0.25), Color.orange.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
}

private struct PeekTile: View {
    let window: WindowInfo
    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let t = window.thumbnail {
                        Image(nsImage: t).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        PeekPlaceholder()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                // Glass sheen along the top edge, brighter on hover.
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(hovering ? 0.10 : 0.05), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.65) : .white.opacity(0.10),
                                  lineWidth: hovering ? 1.2 : 1))

                if hovering {
                    HStack(spacing: 4) {
                        tileBtn("minus", help: "Minimize") { AX.minimizeWindow(pid: window.pid, windowID: window.id) }
                        tileBtn("xmark", help: "Close") { AX.closeWindow(pid: window.pid, windowID: window.id) }
                    }
                    .padding(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .topTrailing)))
                }
            }
            Text(window.title.isEmpty ? "Untitled window" : window.title)
                .font(.system(size: 11, weight: hovering ? .medium : .regular))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .scaleEffect(pressing ? 0.965 : (hovering ? 1.03 : 1.0))
        .offset(y: hovering && !pressing ? -2 : 0)
        .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: hovering ? 10 : 0, y: 4)
        .zIndex(hovering ? 1 : 0)
        .animation(FlowMotion.hoverScale, value: hovering)
        .animation(FlowMotion.press, value: pressing)
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in
                    pressing = false
                    AX.raiseWindow(pid: window.pid, windowID: window.id)
                }
        )
        .help("Click to bring this window to front")
    }

    private func tileBtn(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .frame(width: 19, height: 19)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Small breathing green dot — the "previews are live" heartbeat.
private struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(on ? 2.0 : 1.0)
                    .opacity(on ? 0 : 0.8)
            )
            .onAppear {
                guard !FlowMotion.reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

/// Placeholder for windows we couldn't thumbnail — softly pulsing so the grid
/// still feels alive rather than broken.
private struct PeekPlaceholder: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(
                Image(systemName: "macwindow")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .opacity(pulse ? 0.35 : 0.8)
            )
            .onAppear {
                guard !FlowMotion.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Centralizes enabling Dock previews (request perms, then start the observer).
@MainActor
enum DockPreviewsCoordinator {
    static func enable() {
        if !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
            Permissions.openSettings(.accessibility)
        }
        if !Permissions.hasScreenRecording {
            Permissions.requestScreenRecording()
        }
        DockObserver.shared.start()
    }
}
