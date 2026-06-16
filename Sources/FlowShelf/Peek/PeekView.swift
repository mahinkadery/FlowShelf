import SwiftUI
import AppKit

@MainActor
final class PeekViewModel: ObservableObject {
    @Published var apps: [AppWindows] = []
    @Published var loading = false
    /// Ground-truth: nil = not yet checked, true/false = actual capture result.
    @Published var captureWorks: Bool?

    func refresh() {
        captureWorks = WindowService.shared.canCaptureNow()
        loading = true
        Task {
            let result = await WindowService.shared.allAppWindows(thumbnails: true)
            self.apps = result
            self.loading = false
        }
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
                    "Peek needs this to list each app’s windows, switch to them, and power Dock hover previews. ① Open Settings and turn FlowShelf ON. ② Then Quit & Reopen (the grant only applies on next launch).",
                    pane: .accessibility,
                    showRelaunch: true)
            }
            // Drive this banner off an ACTUAL capture attempt, not the unreliable
            // CGPreflightScreenCaptureAccess flag.
            if Permissions.hasAccessibility && model.captureWorks == false {
                permissionBanner(
                    "Preview capture isn’t working yet",
                    "FlowShelf may already be listed under Screen Recording, but this running build still can’t capture. ① Quit & Reopen. ② If still blank, remove FlowShelf from Screen & System Audio Recording, re-add /Applications/FlowShelf.app, turn it ON, then Quit & Reopen.",
                    pane: .screenRecording,
                    showRelaunch: true)
            }
            content
        }
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Peek").font(.system(size: 15, weight: .semibold))
                Text("Open windows across your apps")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let works = model.captureWorks {
                Label(works ? "Capture working" : "No capture",
                      systemImage: works ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(works ? .green : .orange)
                    .help(works ? "FlowShelf can capture window previews."
                          : "FlowShelf can't capture yet — see the banner below.")
            }
            Toggle(isOn: $settings.dockPreviewsEnabled) {
                Text("Dock hover previews").font(.system(size: 11))
            }
            .toggleStyle(.switch).controlSize(.small)
            .onChange(of: settings.dockPreviewsEnabled) { _, on in
                if on { DockPreviewsCoordinator.enable() } else { DockObserver.shared.stop() }
            }
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }.help("Refresh")
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if model.loading && model.apps.isEmpty {
            VStack { Spacer(); ProgressView("Capturing windows…").controlSize(.small); Spacer() }
                .frame(maxWidth: .infinity)
        } else if model.apps.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "macwindow.on.rectangle").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text(Permissions.hasAccessibility ? "No open windows found"
                     : "Grant Accessibility above to see open windows")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.apps) { app in
                        appSection(app)
                    }
                }
                .padding(14)
            }
        }
    }

    private func appSection(_ app: AppWindows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(app.appName).font(.system(size: 13, weight: .medium))
                Text("\(app.windows.count)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(app.windows) { w in
                    PeekTile(window: w)
                }
            }
        }
    }

    private func permissionBanner(_ title: String, _ detail: String, pane: Permissions.Pane,
                                  showRelaunch: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
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
        .padding(10)
        .background(Color.orange.opacity(0.08))
    }
}

private struct PeekTile: View {
    let window: WindowInfo
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let t = window.thumbnail {
                        Image(nsImage: t).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
                            .overlay(Image(systemName: "macwindow").foregroundStyle(.secondary))
                            .frame(height: 110)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))

                if hovering {
                    HStack(spacing: 4) {
                        tileBtn("minus") { AX.minimizeWindow(pid: window.pid, windowID: window.id) }
                        tileBtn("xmark") { AX.closeWindow(pid: window.pid, windowID: window.id) }
                    }.padding(5)
                }
            }
            Text(window.title).font(.system(size: 11)).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { AX.raiseWindow(pid: window.pid, windowID: window.id) }
    }

    private func tileBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18).background(Circle().fill(.ultraThinMaterial))
        }.buttonStyle(.plain)
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
