import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, shelf, shortcuts, captureAI, privacyPermissions, about

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return L10n.text("General")
        case .shelf: return L10n.text("Shelf")
        case .shortcuts: return L10n.text("Shortcuts")
        case .captureAI: return L10n.text("Capture & AI")
        case .privacyPermissions: return L10n.text("Privacy & Permissions")
        case .about: return L10n.text("About")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shelf: return "tray.full"
        case .shortcuts: return "keyboard"
        case .captureAI: return "camera.viewfinder"
        case .privacyPermissions: return "hand.raised.fill"
        case .about: return "info.circle"
        }
    }
    var searchIndex: [String] {
        switch self {
        case .general:
            return [
                L10n.text("general launch login startup floating shelf shake summon cursor mouse wiggle"),
                L10n.text("peek dock hover previews thumbnails accessibility screen recording size delay"),
            ]
        case .shelf:
            return [
                L10n.text("clipboard capture history active paused private mode disabled retention keep items"),
                L10n.text("storage items shelf clear all pinned disk"),
            ]
        case .shortcuts:
            return [
                L10n.text("window switcher alt option tab shortcut keyboard modifiers thumbnails list accessibility"),
                L10n.text("window snapping snap shortcuts halves quarters maximize center accessibility"),
                L10n.text("shortcuts hotkeys keyboard floating shelf search screenshot ocr dashboard conflicts"),
            ]
        case .captureAI:
            return [
                L10n.text("screenshots screenshot capture annotate annotation arrows boxes highlight blur text editor"),
                L10n.text("image screenshot text search ocr index scan recognize local privacy"),
                L10n.text("on device ai apple intelligence summarize clean ask smart search auto title"),
            ]
        case .privacyPermissions:
            return [
                L10n.text("privacy excluded apps bundle password clipboard"),
                L10n.text("privacy ignored clipboard types rules confidential transient generated markers"),
                L10n.text("permissions accessibility screen recording input monitoring full disk access health required optional"),
            ]
        case .about:
            return [
                L10n.text("software updates version welcome onboarding setup tour"),
                L10n.text("support coffee donate developer about"),
                L10n.text("credits artwork airpods attribution license jed falcone"),
            ]
        }
    }
}

struct SettingsView: View {
    /// When nil (e.g. inside the dashboard) the back button is hidden.
    var onBack: (() -> Void)?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var clipboard = ClipboardMonitor.shared
    @State private var newExclude = ""
    @State private var settingsQuery = ""
    @State private var selectedCategory: SettingsCategory = .general
    @State private var showClearConfirmation = false

    /// Marketing version + build, read from the bundle (single source of truth).
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    Label(L10n.text("Back"), systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.top, 12)
            }

            PaneHeader(icon: "gearshape.fill", tint: Color(white: 0.45),
                       title: L10n.text("Settings"), subtitle: L10n.text("Make FlowShelf yours"))

            if onBack == nil {
                HStack(spacing: 0) {
                    categorySidebar
                    Divider()
                    settingsDetail
                }
            } else {
                compactCategoryPicker
                settingsDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            settingsSearchField
                .padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if settingsQuery.isEmpty || hasSearchResults {
                        categoryContent
                    } else {
                        emptySearchState
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                    settingsQuery = ""
                } label: {
                    Label(category.label, systemImage: category.symbol)
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedCategory == category
                                  ? Color.accentColor.opacity(0.16) : .clear))
                        .foregroundStyle(selectedCategory == category ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .background(Color.primary.opacity(0.025))
    }

    private var compactCategoryPicker: some View {
        Picker(L10n.text("Settings category"), selection: $selectedCategory) {
            ForEach(SettingsCategory.allCases) { category in
                Label(category.label, systemImage: category.symbol).tag(category)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .onChange(of: selectedCategory) { _, _ in settingsQuery = "" }
    }

    @ViewBuilder private var categoryContent: some View {
        switch selectedCategory {
        case .general:
            generalSettings
        case .shelf:
            shelfSettings
        case .shortcuts:
            shortcutSettings
        case .captureAI:
            captureAISettings
        case .privacyPermissions:
            privacySettings
        case .about:
            aboutSettings
        }
    }

    @ViewBuilder private var generalSettings: some View {
        if matches(L10n.text("general launch login startup")) {
            section(L10n.text("App"))
            EmblemRow(icon: "power", tint: .gray, title: L10n.text("Launch at login"),
                      caption: L10n.text("Start FlowShelf automatically when you sign in")) {
                Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .onChange(of: settings.launchAtLogin) { _, on in LoginItem.setEnabled(on) }
            }
        }
        if matches(L10n.text("floating shelf shake summon cursor mouse wiggle")) {
            section(L10n.text("Floating shelf"))
            EmblemRow(icon: "cursorarrow.motionlines", tint: .cyan, title: L10n.text("Shake to summon"),
                      caption: L10n.text("Quickly wiggle the pointer left-right to pop the shelf open at the cursor")) {
                Toggle("", isOn: $settings.shakeToSummon).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .onChange(of: settings.shakeToSummon) { _, on in
                        on ? ShakeDetector.shared.start() : ShakeDetector.shared.stop()
                    }
            }
        }
        if matches(L10n.text("peek dock hover previews thumbnails accessibility screen recording size delay")) {
            section(L10n.text("Peek — Dock previews"))
            EmblemRow(icon: "rectangle.on.rectangle", tint: .blue, title: L10n.text("Dock hover previews"),
                      caption: L10n.text("Live window thumbnails when you hover Dock icons — needs Accessibility and Screen Recording")) {
                Toggle("", isOn: $settings.dockPreviewsEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .onChange(of: settings.dockPreviewsEnabled) { _, on in
                        on ? DockPreviewsCoordinator.enable() : DockObserver.shared.stop()
                    }
            }
            EmblemRow(icon: "arrow.up.left.and.arrow.down.right", tint: .blue,
                      title: L10n.text("Preview size"), caption: L10n.text("How big the hover thumbnails appear")) {
                Picker("", selection: $settings.dockPreviewSize) {
                    ForEach(DockPreviewSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            .disabled(!settings.dockPreviewsEnabled)
            .opacity(settings.dockPreviewsEnabled ? 1 : 0.55)
            EmblemRow(icon: "timer", tint: .blue, title: L10n.text("Hover delay"),
                      caption: String(format: L10n.text("%.2fs before a preview appears"), settings.dockPreviewHoverDelay)) {
                Slider(value: $settings.dockPreviewHoverDelay, in: 0.05...0.8)
                    .controlSize(.small).frame(width: 170)
            }
            .disabled(!settings.dockPreviewsEnabled)
            .opacity(settings.dockPreviewsEnabled ? 1 : 0.55)
        }
    }

    @ViewBuilder private var shelfSettings: some View {
        if matches(L10n.text("clipboard capture history active paused private mode disabled retention keep items")) {
            section(L10n.text("Clipboard"))
            clipboardCaptureRow
            EmblemRow(icon: "clock.arrow.circlepath", tint: .yellow, title: L10n.text("Keep items for"),
                      caption: settings.clipboardRetention.isForever
                        ? L10n.text("Permanent keeps everything forever — storage use can grow over time")
                        : L10n.text("Items clear automatically after 24 hours unless pinned")) {
                Picker("", selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                .onChange(of: settings.clipboardRetention) { _, _ in store.applyRetentionChange() }
            }
        }
        if matches(L10n.text("storage items shelf clear all pinned disk")) {
            section(L10n.text("Storage"))
            EmblemRow(icon: "internaldrive", tint: .brown,
                      title: L10n.text("\(store.visibleItems.count) items on shelf"),
                      caption: L10n.text("Everything currently stored, pinned items included")) {
                Button(L10n.text("Clear…")) { showClearConfirmation = true }
                    .controlSize(.small)
            }
            .confirmationDialog(
                L10n.text("Clear shelf items?"),
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.text("Clear Unpinned Items")) {
                    store.clearAll(includingPinned: false)
                }
                Button(L10n.text("Clear Everything, Including Pinned"), role: .destructive) {
                    store.clearAll(includingPinned: true)
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("This removes stored images and files from FlowShelf. Clearing everything cannot be undone."))
            }
        }
    }

    @ViewBuilder private var shortcutSettings: some View {
        if matches(L10n.text("window switcher alt option tab shortcut keyboard modifiers thumbnails list accessibility")) {
            section(L10n.text("Window switcher"))
            EmblemRow(icon: "rectangle.stack", tint: .indigo, title: L10n.text("Window switcher"),
                      caption: L10n.text("Press the shortcut to advance, release its modifiers to switch, or press Esc to cancel")) {
                Toggle("", isOn: $settings.altTabEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .onChange(of: settings.altTabEnabled) { _, on in
                        if on {
                            if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                            AltTabController.shared.start()
                        } else { AltTabController.shared.stop() }
                    }
            }
            EmblemRow(icon: "keyboard", tint: .indigo, title: L10n.text("Switcher shortcut"),
                      caption: L10n.text("Choose any modifier-and-key combination")) { AltTabShortcutRecorder() }
            EmblemRow(icon: "rectangle.grid.2x2", tint: .indigo, title: L10n.text("Switcher layout"),
                      caption: L10n.text("Big window thumbnails, or a compact list")) {
                Picker("", selection: $settings.altTabLayout) {
                    ForEach(AltTabLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            .disabled(!settings.altTabEnabled)
            .opacity(settings.altTabEnabled ? 1 : 0.55)
        }
        if matches(L10n.text("window snapping snap shortcuts halves quarters maximize center accessibility")) {
            section(L10n.text("Window snapping"))
            EmblemRow(icon: "rectangle.split.2x2", tint: .teal, title: L10n.text("Window snapping"),
                      caption: L10n.text("Move the focused window into halves, quarters, maximize or center")) {
                Toggle("", isOn: $settings.windowSnapEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .onChange(of: settings.windowSnapEnabled) { _, on in
                        if on {
                            if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                            WindowSnapManager.shared.start()
                        } else { WindowSnapManager.shared.stop() }
                    }
            }
            WindowSnapShortcutsEditor()
        }
        if matches(L10n.text("shortcuts hotkeys keyboard floating shelf search screenshot ocr dashboard conflicts")) {
            section(L10n.text("FlowShelf shortcuts"))
            ShortcutsEditor()
        }
    }

    @ViewBuilder private var captureAISettings: some View {
        if matches(L10n.text("screenshots screenshot capture annotate annotation arrows boxes highlight blur text editor")) {
            section(L10n.text("Screenshots"))
            EmblemRow(icon: "camera.viewfinder", tint: .pink, title: L10n.text("Annotate after screenshot"),
                      caption: L10n.text("Open the editor after capture — arrows, boxes, highlight, blur and text")) {
                Toggle("", isOn: $settings.annotateAfterScreenshot).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
        }
        if matches(L10n.text("image screenshot text search ocr index scan recognize local privacy")) {
            section(L10n.text("Image text search"))
            ImageTextSearchSettings()
        }
        if matches(L10n.text("on device ai apple intelligence summarize clean ask smart search auto title")) {
            section(L10n.text("On-device AI"))
            aiRows
        }
    }

    @ViewBuilder private var privacySettings: some View {
        if matches(L10n.text("privacy excluded apps bundle password clipboard")) {
            section(L10n.text("Clipboard privacy"))
            excludedCard
        }
        if matches(L10n.text("privacy ignored clipboard types rules confidential transient generated markers")) {
            section(L10n.text("Ignored clipboard types"))
            ClipboardPrivacySettings()
        }
        if matches(L10n.text("permissions accessibility screen recording input monitoring full disk access health required optional")) {
            section(L10n.text("Permission health"))
            permissionOverviewCard
        }
    }

    @ViewBuilder private var aboutSettings: some View {
        if matches(L10n.text("software updates version welcome onboarding setup tour")) {
            section("FlowShelf")
            EmblemRow(icon: "arrow.triangle.2.circlepath", tint: .gray,
                      title: L10n.text("Software updates"), caption: L10n.text("You're on \(Self.appVersion)")) {
                Button(L10n.text("Check for Updates…")) { UpdaterManager.shared.checkForUpdates() }
                    .controlSize(.small)
            }
            EmblemRow(icon: "sparkles.rectangle.stack", tint: .orange,
                      title: L10n.text("Welcome & setup"), caption: L10n.text("Replay the visual tour at any time")) {
                Button(L10n.text("Show Welcome…")) { OnboardingController.shared.show() }
                    .controlSize(.small)
            }
        }
        if matches(L10n.text("support coffee donate developer about")) {
            section(L10n.text("Support"))
            supportCard
        }
        if matches(L10n.text("credits artwork airpods attribution license jed falcone")) {
            section(L10n.text("Artwork credits"))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("AirPods Pro 3D model by Jed Falcone"))
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.text("Adapted into a short rendered animation for FlowShelf. Licensed under CC BY 4.0. No Apple endorsement implied."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link(L10n.text("Original model"), destination: URL(string: "https://sketchfab.com/3d-models/airpods-pro-3f84ddc3d87a4ec0a5e5f379abfecd9c")!)
                    Link(L10n.text("CC BY 4.0 license"), destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
                .font(.system(size: 11))
            }
            .padding(13)
            .raisedCard()
        }
        if settingsQuery.isEmpty {
            Text(L10n.text("FlowShelf \(Self.appVersion) — a smarter temporary shelf for your Mac."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Pieces

    private var settingsSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L10n.text("Search settings…"), text: $settingsQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !settingsQuery.isEmpty {
                Button { settingsQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.text("Clear search"))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .raisedCard(cornerRadius: 10)
        .padding(.horizontal, 18)
        .accessibilityLabel(L10n.text("Search settings"))
    }

    private func matches(_ searchableText: String) -> Bool {
        let tokens = settingsQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return tokens.isEmpty || tokens.allSatisfy {
            searchableText.localizedCaseInsensitiveContains($0)
        }
    }

    private var hasSearchResults: Bool {
        selectedCategory.searchIndex.contains { matches($0) }
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.text("No settings found in \(selectedCategory.label)"))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.text("Try another term or choose a different category."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var clipboardCaptureBinding: Binding<ClipboardCaptureState> {
        Binding(
            get: { settings.clipboardCaptureState },
            set: { settings.clipboardCaptureState = $0 }
        )
    }

    private var clipboardCaptureCaption: String {
        switch settings.clipboardCaptureState {
        case .active:
            return clipboard.accessWarning ?? L10n.text("New copies are automatically added to your shelf")
        case .paused:
            return L10n.text("Temporarily paused — nothing is recorded until you resume")
        case .disabled:
            return L10n.text("Clipboard monitoring is completely turned off")
        }
    }

    private var clipboardCaptureTint: Color {
        switch settings.clipboardCaptureState {
        case .active: return clipboard.accessWarning == nil ? .green : .orange
        case .paused: return .orange
        case .disabled: return .gray
        }
    }

    private var clipboardCaptureRow: some View {
        EmblemRow(icon: settings.clipboardCaptureState.symbol, tint: clipboardCaptureTint,
                  title: L10n.text("Clipboard capture"), caption: clipboardCaptureCaption) {
            Picker(L10n.text("Clipboard capture"), selection: clipboardCaptureBinding) {
                ForEach(ClipboardCaptureState.allCases) { state in
                    Text(state.label).tag(state)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var accessibilityRequired: Bool {
        settings.dockPreviewsEnabled || settings.altTabEnabled || settings.windowSnapEnabled
    }

    private var inputMonitoringRequired: Bool {
        settings.notchEnabled && settings.notchHUDEnabled
    }

    private var requiredPermissionStates: [Bool] {
        var states = [Permissions.hasScreenRecording]
        if accessibilityRequired { states.append(Permissions.hasAccessibility) }
        if inputMonitoringRequired { states.append(Permissions.hasInputMonitoring) }
        return states
    }

    private var permissionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                EmblemChip(icon: "checkmark.shield", tint: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Required access"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("\(requiredPermissionStates.filter { $0 }.count) of \(requiredPermissionStates.count) permissions required by your enabled features are ready"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            permissionStatusLine(L10n.text("Screen Recording"), required: true,
                                 granted: Permissions.hasScreenRecording)
            permissionStatusLine(L10n.text("Accessibility"), required: accessibilityRequired,
                                 granted: Permissions.hasAccessibility)
            permissionStatusLine(L10n.text("Input Monitoring"), required: inputMonitoringRequired,
                                 granted: Permissions.hasInputMonitoring)

            Button {
                DashboardWindowController.shared.show(section: .permissions)
            } label: {
                Label(L10n.text("Open Permission Health"), systemImage: "arrow.right.circle")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .raisedCard()
    }

    private func permissionStatusLine(_ title: String, required: Bool, granted: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 11.5, weight: .medium))
            Spacer()
            Text(granted ? L10n.text("Granted") : (required ? L10n.text("Required") : L10n.text("Optional")))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(granted ? Color.green : (required ? Color.orange : Color.secondary))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(
                    (granted ? Color.green : (required ? Color.orange : Color.secondary)).opacity(0.12)
                ))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.045)))
    }

    /// Slim uppercase section label between emblem-row groups.
    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
            .padding(.leading, 6).padding(.top, 10).padding(.bottom, 2)
    }

    @ViewBuilder private var aiRows: some View {
        if AIService.isSupported {
            EmblemRow(icon: "sparkles", tint: .purple,
                      title: L10n.text("AI actions"),
                      caption: L10n.text("Summarize · clean up · ask · smart search — Apple Intelligence, fully on your Mac, runs only when you ask")) {
                Toggle("", isOn: $settings.aiEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
            EmblemRow(icon: "character.cursor.ibeam", tint: .purple,
                      title: L10n.text("Auto-title new text items"),
                      caption: L10n.text("Names items as you copy them — off by default to save battery/RAM")) {
                Toggle("", isOn: $settings.aiAutoTitle).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!settings.aiEnabled)
            }
        } else {
            EmblemRow(icon: "sparkles", tint: .orange,
                      title: L10n.text("On-device AI not available yet"),
                      caption: AIService.statusMessage) {
                Button(L10n.text("Open settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.intelligence") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var excludedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                EmblemChip(icon: "hand.raised.fill", tint: .mint)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(L10n.text("Excluded apps")).font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("Copies from these apps are never recorded"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(settings.excludedBundleIDs, id: \.self) { id in
                HStack {
                    Text(id).font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Button { settings.excludedBundleIDs.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05)))
            }
            HStack {
                TextField("com.example.app", text: $newExclude)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06)))
                Button(L10n.text("Add")) {
                    let id = newExclude.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !settings.excludedBundleIDs.contains(id) else { return }
                    settings.excludedBundleIDs.append(id); newExclude = ""
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .raisedCard()
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                EmblemChip(icon: "heart.fill", tint: .red)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(L10n.text("Support FlowShelf")).font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("FlowShelf is free — if it saves you time, you can buy me a coffee ☕️"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
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
                    Label(L10n.text("Buy Me a Coffee"), systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.orange)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain).help("buymeacoffee.com/mahinkadery")
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .raisedCard()
    }
}
