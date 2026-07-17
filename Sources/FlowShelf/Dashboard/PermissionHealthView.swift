import AppKit
import SwiftUI

struct PermissionHealthView: View {
    @State private var refreshID = UUID()

    private var grantedCount: Int {
        [Permissions.hasAccessibility,
         Permissions.hasScreenRecording,
         Permissions.hasInputMonitoring].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                icon: "checkmark.shield",
                tint: .teal,
                title: "Permissions",
                subtitle: "See exactly what FlowShelf can access — and why"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    healthSummary

                    PermissionRow(
                        icon: "figure.wave",
                        tint: .blue,
                        title: "Accessibility",
                        detail: "Window snapping, Dock previews, and the window switcher use this to read and move windows.",
                        isGranted: Permissions.hasAccessibility,
                        request: { Permissions.requestAccessibility() },
                        openSettings: { Permissions.openSettings(.accessibility) }
                    )

                    PermissionRow(
                        icon: "rectangle.inset.filled.and.person.filled",
                        tint: .purple,
                        title: "Screen Recording",
                        detail: "Screenshots, window thumbnails, and the notch lens need this to capture pixels from other apps.",
                        isGranted: Permissions.hasScreenRecording,
                        request: { Permissions.requestScreenRecording() },
                        openSettings: { Permissions.openSettings(.screenRecording) }
                    )

                    PermissionRow(
                        icon: "keyboard.badge.eye",
                        tint: .orange,
                        title: "Input Monitoring",
                        detail: "Optional. Lets the notch show volume and brightness changes from hardware keys.",
                        isGranted: Permissions.hasInputMonitoring,
                        request: { Permissions.requestInputMonitoring() },
                        openSettings: { Permissions.openSettings(.inputMonitoring) }
                    )

                    OptionalPermissionRow(
                        icon: "externaldrive.badge.checkmark",
                        tint: .green,
                        title: "Full Disk Access",
                        status: "Optional",
                        detail: "Only useful for Cleaner when macOS protects leftover files in Library folders.",
                        actionTitle: "Open Settings",
                        action: { Permissions.openSettings(.fullDiskAccess) }
                    )

                    OptionalPermissionRow(
                        icon: "bell.slash",
                        tint: .gray,
                        title: "Notifications",
                        status: "Not required",
                        detail: "FlowShelf currently does not send notifications, so it never asks for notification access.",
                        actionTitle: nil,
                        action: {}
                    )

                    Text("FlowShelf asks only when a feature needs access. macOS may require restarting FlowShelf after you change a privacy permission.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(18)
                .id(refreshID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var healthSummary: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.09), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(grantedCount) / 3)
                    .stroke(.teal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(grantedCount)/3")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(grantedCount == 3 ? "Feature access is ready" : "Some features need access")
                    .font(.system(size: 15, weight: .semibold))
                Text("Optional permissions can stay off until you use the related feature.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(14)
        .raisedCard(cornerRadius: 14)
    }

    private func refresh() {
        refreshID = UUID()
    }
}

private struct PermissionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EmblemChip(icon: icon, tint: tint, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    StatusBadge(label: isGranted ? "Granted" : "Missing", isPositive: isGranted)
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 7) {
                    Button("Ask macOS") { _ = request() }
                        .controlSize(.small)
                    Button("Settings") { openSettings() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .raisedCard()
    }
}

private struct OptionalPermissionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let status: String
    let detail: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EmblemChip(icon: icon, tint: tint, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    StatusBadge(label: status, isPositive: true)
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let actionTitle {
                Button(actionTitle) { action() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .raisedCard()
    }
}

private struct StatusBadge: View {
    let label: String
    let isPositive: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(isPositive ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((isPositive ? Color.green : Color.orange).opacity(0.12)))
    }
}
