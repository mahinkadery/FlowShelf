import SwiftUI

struct SettingsView: View {
    /// When nil (e.g. inside the dashboard) the back button is hidden.
    var onBack: (() -> Void)?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = ShelfStore.shared
    @State private var newExclude = ""
    @State private var settingsQuery = ""

    /// Marketing version + build, read from the bundle (single source of truth).
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let onBack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.top, 12)
                }

                PaneHeader(icon: "gearshape.fill", tint: Color(white: 0.45),
                           title: "Settings", subtitle: "Make FlowShelf yours")

                settingsSearchField

                Group {
                    if matches("general launch login startup software updates version welcome onboarding setup tour") {
                        section("General")
                        EmblemRow(icon: "power", tint: .gray,
                                  title: "Launch at login",
                                  caption: "Start FlowShelf automatically when you sign in") {
                            Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                                .toggleStyle(.switch).controlSize(.small)
                                .onChange(of: settings.launchAtLogin) { _, on in LoginItem.setEnabled(on) }
                        }
                        EmblemRow(icon: "arrow.triangle.2.circlepath", tint: .gray,
                                  title: "Software updates",
                                  caption: "You're on \(Self.appVersion)") {
                            Button("Check for Updates…") { UpdaterManager.shared.checkForUpdates() }
                                .controlSize(.small)
                        }
                        EmblemRow(icon: "sparkles.rectangle.stack", tint: .orange,
                                  title: "Welcome & setup",
                                  caption: "Replay the visual tour or review FlowShelf with someone new") {
                            Button("Show Welcome…") { OnboardingController.shared.show() }
                                .controlSize(.small)
                        }
                    }

                    if matches("peek dock hover previews thumbnails accessibility screen recording size delay") {
                        section("Peek — Dock previews")
                        EmblemRow(icon: "rectangle.on.rectangle", tint: .blue,
                                  title: "Dock hover previews",
                                  caption: "Live window thumbnails when you hover Dock icons — needs Accessibility (and Screen Recording)") {
                            Toggle("", isOn: $settings.dockPreviewsEnabled).labelsHidden()
                                .toggleStyle(.switch).controlSize(.small)
                                .onChange(of: settings.dockPreviewsEnabled) { _, on in
                                    on ? DockPreviewsCoordinator.enable() : DockObserver.shared.stop()
                                }
                        }
                        EmblemRow(icon: "arrow.up.left.and.arrow.down.right", tint: .blue,
                                  title: "Preview size",
                                  caption: "How big the hover thumbnails appear") {
                            Picker("", selection: $settings.dockPreviewSize) {
                                ForEach(DockPreviewSize.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                        }
                        .disabled(!settings.dockPreviewsEnabled)
                        .opacity(settings.dockPreviewsEnabled ? 1 : 0.55)
                        EmblemRow(icon: "timer", tint: .blue,
                                  title: "Hover delay",
                                  caption: String(format: "%.2fs before a preview appears", settings.dockPreviewHoverDelay)) {
                            Slider(value: $settings.dockPreviewHoverDelay, in: 0.05...0.8)
                                .controlSize(.small).frame(width: 170)
                        }
                        .disabled(!settings.dockPreviewsEnabled)
                        .opacity(settings.dockPreviewsEnabled ? 1 : 0.55)
                    }

                    if matches("window switcher alt option tab shortcut keyboard command control shift modifiers thumbnails list accessibility permission") {
                        section("Window switcher")
                        EmblemRow(icon: "rectangle.stack", tint: .indigo,
                                  title: "Window switcher",
                                  caption: "Press your shortcut to advance · add Shift to go back when available · release its modifiers to switch · Esc cancels") {
                            Toggle("", isOn: $settings.altTabEnabled).labelsHidden()
                                .toggleStyle(.switch).controlSize(.small)
                                .onChange(of: settings.altTabEnabled) { _, on in
                                    if on {
                                        if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                                        AltTabController.shared.start()
                                    } else {
                                        AltTabController.shared.stop()
                                    }
                                }
                        }
                        EmblemRow(icon: "keyboard", tint: .indigo,
                                  title: "Switcher shortcut",
                                  caption: "Choose any modifier-and-key combination") {
                            AltTabShortcutRecorder()
                        }
                        EmblemRow(icon: "rectangle.grid.2x2", tint: .indigo,
                                  title: "Switcher layout",
                                  caption: "Big window thumbnails, or a compact list") {
                            Picker("", selection: $settings.altTabLayout) {
                                ForEach(AltTabLayout.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                        }
                        .disabled(!settings.altTabEnabled)
                        .opacity(settings.altTabEnabled ? 1 : 0.55)
                    }
                }
                .padding(.horizontal, 18)

                Group {
                    if matches("window snapping snap shortcuts keyboard command control option shift modifiers halves quarters maximize center accessibility permission") {
                        section("Window snapping")
                        EmblemRow(icon: "rectangle.split.2x2", tint: .teal,
                                  title: "Window snapping",
                                  caption: "Move the focused window into halves, quarters, maximize or center. Needs Accessibility") {
                            Toggle("", isOn: $settings.windowSnapEnabled).labelsHidden()
                                .toggleStyle(.switch).controlSize(.small)
                                .onChange(of: settings.windowSnapEnabled) { _, on in
                                    if on {
                                        if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                                        WindowSnapManager.shared.start()
                                    } else {
                                        WindowSnapManager.shared.stop()
                                    }
                                }
                        }
                        WindowSnapShortcutsEditor()
                    }

                    if matches("notch shelf island media now playing audio reactive bars volume brightness charging hud") {
                        section("Notch")
                        EmblemRow(icon: "tray.and.arrow.down.fill", tint: .orange,
                              title: "Notch shelf",
                              caption: "A Dynamic-Island shelf in the notch — drop files, images or text to shelve them") {
                        Toggle("", isOn: $settings.notchEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .onChange(of: settings.notchEnabled) { _, on in
                                on ? NotchController.shared.start() : NotchController.shared.stop()
                            }
                    }
                        EmblemRow(icon: "music.note", tint: .pink,
                              title: "Now-playing media",
                              caption: "Album art + live activity when collapsed, compact player when open — fully on-device") {
                        Toggle("", isOn: $settings.notchMediaEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!settings.notchEnabled)
                    }
                        EmblemRow(icon: "waveform", tint: .purple,
                              title: "Audio-reactive bars",
                              caption: "Bars dance to the actual music (shows the macOS recording indicator)") {
                        Toggle("", isOn: $settings.audioReactiveBars).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!settings.notchEnabled || !settings.notchMediaEnabled)
                    }
                        EmblemRow(icon: "speaker.wave.2.fill", tint: .blue,
                              title: "Volume, brightness & charging HUDs",
                              caption: "Sleek notch HUDs instead of Apple's centre-screen overlay — volume/brightness need Input Monitoring") {
                        Toggle("", isOn: $settings.notchHUDEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!settings.notchEnabled)
                            .onChange(of: settings.notchHUDEnabled) { _, on in
                                on ? SystemHUDMonitor.shared.start() : SystemHUDMonitor.shared.stop()
                            }
                        }
                    }

                    if matches("screenshots screenshot capture annotate annotation arrows boxes highlight blur text editor") {
                        section("Screenshots")
                        EmblemRow(icon: "camera.viewfinder", tint: .pink,
                              title: "Annotate after screenshot",
                              caption: "Open the editor after capture — arrows, boxes, highlight, blur, text") {
                        Toggle("", isOn: $settings.annotateAfterScreenshot).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                        }
                    }

                    if matches("on device ai apple intelligence summarize clean ask smart search auto title") {
                        section("On-device AI")
                        aiRows
                    }
                }
                .padding(.horizontal, 18)

                Group {
                    if matches("clipboard history private mode retention keep items excluded apps bundle password") {
                        section("Clipboard")
                        EmblemRow(icon: "doc.on.clipboard", tint: .yellow,
                              title: "Record clipboard history",
                              caption: "Everything you copy lands on the shelf") {
                        Toggle("", isOn: $settings.clipboardEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                    }
                        EmblemRow(icon: "eye.slash", tint: .yellow,
                              title: "Private mode",
                              caption: "Pause capture — nothing is recorded while on") {
                        Toggle("", isOn: $settings.privateMode).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                    }
                        EmblemRow(icon: "clock.arrow.circlepath", tint: .yellow,
                              title: "Keep items for",
                              caption: settings.clipboardRetention.isForever
                                ? "⚠️ Permanent keeps everything forever — it can get large; items never auto-clear"
                                : "Items clear automatically after 24 hours unless pinned") {
                        Picker("", selection: $settings.clipboardRetention) {
                            ForEach(ClipboardRetention.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                        .onChange(of: settings.clipboardRetention) { _, _ in
                            store.applyRetentionChange()
                        }
                    }
                        excludedCard
                    }

                    if matches("floating shelf shake summon cursor mouse wiggle") {
                        section("Floating shelf")
                        EmblemRow(icon: "cursorarrow.motionlines", tint: .cyan,
                              title: "Shake to summon",
                              caption: "Quickly wiggle the pointer left-right to pop the shelf open at the cursor") {
                        Toggle("", isOn: $settings.shakeToSummon).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .onChange(of: settings.shakeToSummon) { _, on in
                                on ? ShakeDetector.shared.start() : ShakeDetector.shared.stop()
                            }
                        }
                    }

                    if matches("shortcuts hotkeys keyboard floating shelf search screenshot ocr dashboard conflicts") {
                        section("Shortcuts")
                        ShortcutsEditor()
                    }

                    if matches("storage items shelf clear all pinned disk") {
                        section("Storage")
                        EmblemRow(icon: "internaldrive", tint: .brown,
                              title: "\(store.visibleItems.count) items on shelf",
                              caption: "Everything currently stored, pinned items included") {
                        Button("Clear all") { store.clearAll(includingPinned: true) }
                            .controlSize(.small)
                        }
                    }

                    if matches("support coffee donate developer") {
                        section("Support")
                        supportCard
                    }

                    if settingsQuery.isEmpty {
                        Text("FlowShelf \(Self.appVersion) — a smarter temporary shelf for your Mac.")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
                    } else if !hasSearchResults {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("No settings found")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Try a feature name, permission, or shortcut action.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Pieces

    private static let searchIndex = [
        "general launch login startup software updates version welcome onboarding setup tour",
        "peek dock hover previews thumbnails accessibility screen recording size delay",
        "window switcher alt option tab shortcut keyboard command control shift modifiers thumbnails list accessibility permission",
        "window snapping snap shortcuts keyboard command control option shift modifiers halves quarters maximize center accessibility permission",
        "notch shelf island media now playing audio reactive bars volume brightness charging hud",
        "screenshots screenshot capture annotate annotation arrows boxes highlight blur text editor",
        "on device ai apple intelligence summarize clean ask smart search auto title",
        "clipboard history private mode retention keep items excluded apps bundle password",
        "floating shelf shake summon cursor mouse wiggle",
        "shortcuts hotkeys keyboard floating shelf search screenshot ocr dashboard conflicts",
        "storage items shelf clear all pinned disk",
        "support coffee donate developer",
    ]

    private var settingsSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search settings…", text: $settingsQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !settingsQuery.isEmpty {
                Button { settingsQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .raisedCard(cornerRadius: 10)
        .padding(.horizontal, 18)
        .accessibilityLabel("Search settings")
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
        Self.searchIndex.contains { matches($0) }
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
                      title: "AI actions",
                      caption: "Summarize · clean up · ask · smart search — Apple Intelligence, fully on your Mac, runs only when you ask") {
                Toggle("", isOn: $settings.aiEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
            EmblemRow(icon: "character.cursor.ibeam", tint: .purple,
                      title: "Auto-title new text items",
                      caption: "Names items as you copy them — off by default to save battery/RAM") {
                Toggle("", isOn: $settings.aiAutoTitle).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!settings.aiEnabled)
            }
        } else {
            EmblemRow(icon: "sparkles", tint: .orange,
                      title: "On-device AI not available yet",
                      caption: AIService.statusMessage) {
                Button("Open settings") {
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
                    Text("Excluded apps").font(.system(size: 13, weight: .semibold))
                    Text("Copies from these apps are never recorded")
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
                Button("Add") {
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
                    Text("Support FlowShelf").font(.system(size: 13, weight: .semibold))
                    Text("FlowShelf is free — if it saves you time, you can buy me a coffee ☕️")
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
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
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
