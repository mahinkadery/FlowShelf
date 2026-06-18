import SwiftUI

struct SettingsView: View {
    /// When nil (e.g. inside the dashboard) the back button is hidden.
    var onBack: (() -> Void)?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = ShelfStore.shared
    @State private var newExclude = ""

    /// Marketing version + build, read from the bundle (single source of truth).
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings").font(.system(size: 15, weight: .semibold))
                    Text("Preferences").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    generalCard
                    peekCard
                    switcherCard
                    snapCard
                    notchCard
                    screenshotCard
                    aiCard
                    clipboardCard
                    excludedCard
                    floatingShelfCard
                    shortcutsCard
                    storageCard
                    supportCard
                    Text("FlowShelf \(Self.appVersion) — a smarter temporary shelf for your Mac.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Cards

    private var generalCard: some View {
        card("General", icon: "gearshape") {
            Toggle("Launch FlowShelf at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, on in LoginItem.setEnabled(on) }
            Divider().opacity(0.4)
            HStack {
                Text("Software updates").font(.system(size: 12))
                Spacer()
                Button("Check for Updates…") { UpdaterManager.shared.checkForUpdates() }
                    .controlSize(.small)
            }
        }
    }

    private var peekCard: some View {
        card("Peek — Dock previews", icon: "rectangle.on.rectangle") {
            Toggle("Show window previews when hovering Dock icons", isOn: $settings.dockPreviewsEnabled)
                .onChange(of: settings.dockPreviewsEnabled) { _, on in
                    on ? DockPreviewsCoordinator.enable() : DockObserver.shared.stop()
                }
            Text("Needs Accessibility (and Screen Recording for live thumbnails).")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Divider().opacity(0.4)

            HStack {
                Text("Preview size").font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.dockPreviewSize) {
                    ForEach(DockPreviewSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Hover delay").font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.2fs", settings.dockPreviewHoverDelay))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Slider(value: $settings.dockPreviewHoverDelay, in: 0.05...0.8)
            }
            .disabled(!settings.dockPreviewsEnabled)
            .opacity(settings.dockPreviewsEnabled ? 1 : 0.5)
        }
    }

    private var switcherCard: some View {
        card("Window switcher — ⌥Tab", icon: "rectangle.stack") {
            Toggle("Hold ⌥ and press Tab to switch windows", isOn: $settings.altTabEnabled)
                .onChange(of: settings.altTabEnabled) { _, on in
                    if on {
                        if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                        AltTabController.shared.start()
                    } else {
                        AltTabController.shared.stop()
                    }
                }
            Text("⌥Tab to advance · ⌥⇧Tab back · arrows to move · release ⌥ or Return to switch · Esc to cancel. Needs Accessibility.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)
            HStack {
                Text("Layout").font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.altTabLayout) {
                    ForEach(AltTabLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            .disabled(!settings.altTabEnabled)
            .opacity(settings.altTabEnabled ? 1 : 0.5)
        }
    }

    private var notchCard: some View {
        card("Notch shelf", icon: "macbook") {
            Toggle("Show a Dynamic-Island shelf in the notch", isOn: $settings.notchEnabled)
                .onChange(of: settings.notchEnabled) { _, on in
                    on ? NotchController.shared.start() : NotchController.shared.stop()
                }
            Text("Hover the notch (or top-center pill) to expand it; drop files, images, or text to add them to the shelf. On Macs without a notch it shows as a small pill at the top.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var snapCard: some View {
        card("Window snapping", icon: "rectangle.split.2x2") {
            Toggle("Snap windows with ⌃⌥ + keys", isOn: $settings.windowSnapEnabled)
                .onChange(of: settings.windowSnapEnabled) { _, on in
                    if on {
                        if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                        WindowSnapManager.shared.start()
                    } else {
                        WindowSnapManager.shared.stop()
                    }
                }
            Text("Hold ⌃⌥ (Control-Option) and press a key to move the focused window. Needs Accessibility.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.windowSnapEnabled {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 4) {
                    snapHint("← / →", "Left / right half")
                    snapHint("↑ / ↓", "Top / bottom half")
                    snapHint("U I J K", "Corners (¼ screen)")
                    snapHint("↩  /  C", "Maximize / center")
                }
            }
        }
    }

    private func snapHint(_ keys: String, _ label: String) -> some View {
        HStack {
            Text("⌃⌥ \(keys)")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var aiCard: some View {
        card("On-device AI", icon: "sparkles") {
            if AIService.isSupported {
                Toggle("Show AI actions (summarize · clean up · ask · smart search)", isOn: $settings.aiEnabled)
                Text("Runs entirely on your Mac with Apple Intelligence — no internet, no accounts, no cost. Right-click a text item on the shelf, or hit the ✨ button when searching. Runs only when you ask.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.4)
                Toggle("Auto-title new text items", isOn: $settings.aiAutoTitle)
                    .disabled(!settings.aiEnabled)
                Text("Names items for you as you copy them. Off by default — this runs the AI on capture, so leave it off to save battery/RAM.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Not available yet", systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                Text(AIService.statusMessage)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Apple Intelligence settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.intelligence") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var screenshotCard: some View {
        card("Screenshots", icon: "camera.viewfinder") {
            Toggle("Open the annotation editor after a screenshot", isOn: $settings.annotateAfterScreenshot)
            Text("Mark up captures with arrows, boxes, highlight, blur (to hide sensitive info), and text — then copy, save, or add to the shelf. You can also right-click any image on the shelf and choose “Annotate…”.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var clipboardCard: some View {
        card("Clipboard", icon: "doc.on.clipboard") {
            Toggle("Record clipboard history", isOn: $settings.clipboardEnabled)
            Toggle("Private mode (pause capture)", isOn: $settings.privateMode)

            Divider().opacity(0.4)

            HStack {
                Text("Keep items for").font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                .onChange(of: settings.clipboardRetention) { _, _ in
                    store.applyRetentionChange()
                }
            }
            if settings.clipboardRetention.isForever {
                Label {
                    Text("Permanent keeps everything you copy forever — it can get large and messy over time. Items won’t auto-clear; remove them by hand or switch back to 24 hours.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 11)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Items clear automatically after 24 hours unless pinned.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var excludedCard: some View {
        card("Excluded apps", icon: "hand.raised") {
            Text("Copies from these apps are never recorded.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(settings.excludedBundleIDs, id: \.self) { id in
                HStack {
                    Text(id).font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Button { settings.excludedBundleIDs.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("com.example.app", text: $newExclude)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button("Add") {
                    let id = newExclude.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !settings.excludedBundleIDs.contains(id) else { return }
                    settings.excludedBundleIDs.append(id); newExclude = ""
                }
            }
        }
    }

    private var floatingShelfCard: some View {
        card("Floating shelf", icon: "tray.full") {
            Toggle("Shake the mouse to summon the shelf", isOn: $settings.shakeToSummon)
                .onChange(of: settings.shakeToSummon) { _, on in
                    on ? ShakeDetector.shared.start() : ShakeDetector.shared.stop()
                }
            Text("Quickly wiggle the pointer left-right to pop the shelf open at the cursor.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var shortcutsCard: some View {
        card("Shortcuts", icon: "command") {
            shortcutRow("Open shelf search", "⌘⇧V")
            shortcutRow("Show floating shelf", "⌘⇧S")
            shortcutRow("Screenshot region", "⌘⇧7")
            shortcutRow("Screenshot + OCR", "⌘⇧O")
            shortcutRow("Open dashboard", "⌘⇧D")
        }
    }

    private var storageCard: some View {
        card("Storage", icon: "internaldrive") {
            HStack {
                Text("\(store.visibleItems.count) items on shelf").font(.system(size: 12))
                Spacer()
                Button("Clear all") { store.clearAll(includingPinned: true) }.controlSize(.small)
            }
        }
    }

    private var supportCard: some View {
        card("Support", icon: "heart") {
            Text("FlowShelf is free. If it saves you time, you can buy me a coffee ☕️")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "https://buymeacoffee.com/mahinkadery") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                if let img = Bundle.main.loadImage("buymeacoffee") {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                } else {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.orange)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain).help("buymeacoffee.com/mahinkadery")
            .padding(.top, 2)
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(_ title: String, icon: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06)))
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
        }
    }
}
