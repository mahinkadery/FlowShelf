import AppKit
import SwiftUI

struct PermissionHealthView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var refreshID = UUID()

    private var accessibilityReasons: [String] {
        var reasons: [String] = []
        if settings.windowSnapEnabled { reasons.append("Window snapping") }
        if settings.dockPreviewsEnabled { reasons.append("Dock previews") }
        if settings.altTabEnabled { reasons.append("Window switcher") }
        return reasons
    }

    private var screenRecordingReasons: [String] {
        var reasons = ["Screenshots"]
        if settings.dockPreviewsEnabled { reasons.append("Dock previews") }
        if settings.notchEnabled { reasons.append("Notch lens") }
        return reasons
    }

    private var inputMonitoringRequired: Bool {
        settings.notchEnabled && settings.notchHUDEnabled
    }

    private var requiredPermissionStates: [Bool] {
        var states = [Permissions.hasScreenRecording]
        if !accessibilityReasons.isEmpty { states.append(Permissions.hasAccessibility) }
        if inputMonitoringRequired { states.append(Permissions.hasInputMonitoring) }
        return states
    }

    private var grantedRequiredCount: Int {
        requiredPermissionStates.filter { $0 }.count
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

                    permissionSectionLabel("Required for enabled features")

                    PermissionRow(
                        icon: "rectangle.inset.filled.and.person.filled",
                        tint: .purple,
                        title: "Screen Recording",
                        detail: "Used by \(screenRecordingReasons.joined(separator: ", ")) to capture pixels from other apps.",
                        isRequired: true,
                        isGranted: Permissions.hasScreenRecording,
                        request: { Permissions.requestScreenRecording() },
                        openSettings: { Permissions.openSettings(.screenRecording) }
                    )

                    if !accessibilityReasons.isEmpty {
                        PermissionRow(
                            icon: "figure.wave",
                            tint: .blue,
                            title: "Accessibility",
                            detail: "Used by \(accessibilityReasons.joined(separator: ", ")) to read and move windows.",
                            isRequired: true,
                            isGranted: Permissions.hasAccessibility,
                            request: { Permissions.requestAccessibility() },
                            openSettings: { Permissions.openSettings(.accessibility) }
                        )
                    }

                    if inputMonitoringRequired {
                        PermissionRow(
                            icon: "keyboard.badge.eye",
                            tint: .orange,
                            title: "Input Monitoring",
                            detail: "Used by the enabled Notch volume and brightness HUDs to detect hardware keys.",
                            isRequired: true,
                            isGranted: Permissions.hasInputMonitoring,
                            request: { Permissions.requestInputMonitoring() },
                            openSettings: { Permissions.openSettings(.inputMonitoring) }
                        )
                    }

                    permissionSectionLabel("Optional enhancements")

                    if accessibilityReasons.isEmpty {
                        PermissionRow(
                            icon: "figure.wave",
                            tint: .blue,
                            title: "Accessibility",
                            detail: "Not needed for your current setup. Enable a window feature if you want to use it.",
                            isRequired: false,
                            isGranted: Permissions.hasAccessibility,
                            request: { Permissions.requestAccessibility() },
                            openSettings: { Permissions.openSettings(.accessibility) }
                        )
                    }

                    if !inputMonitoringRequired {
                        PermissionRow(
                            icon: "keyboard.badge.eye",
                            tint: .orange,
                            title: "Input Monitoring",
                            detail: "Optional unless Notch volume and brightness HUDs are enabled.",
                            isRequired: false,
                            isGranted: Permissions.hasInputMonitoring,
                            request: { Permissions.requestInputMonitoring() },
                            openSettings: { Permissions.openSettings(.inputMonitoring) }
                        )
                    }

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
                    .trim(from: 0, to: CGFloat(grantedRequiredCount) / CGFloat(requiredPermissionStates.count))
                    .stroke(.teal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(grantedRequiredCount)/\(requiredPermissionStates.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(grantedRequiredCount == requiredPermissionStates.count
                     ? "Enabled features are ready" : "Enabled features need access")
                    .font(.system(size: 15, weight: .semibold))
                Text("Only permissions required by your current setup affect this score.")
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

    private func permissionSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }
}

private struct PermissionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let isRequired: Bool
    let isGranted: Bool
    let request: () -> Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EmblemChip(icon: icon, tint: tint, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    StatusBadge(
                        label: isGranted ? "Granted" : (isRequired ? "Required" : "Optional"),
                        tint: isGranted ? .green : (isRequired ? .orange : .secondary)
                    )
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
                    StatusBadge(label: status, tint: .secondary)
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
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}
