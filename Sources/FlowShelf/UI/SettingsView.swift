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
                VStack(alignment: .leading, spacing: 18) {
                    section("General") {
                        Toggle("Launch FlowShelf at login", isOn: $settings.launchAtLogin)
                            .onChange(of: settings.launchAtLogin) { _, on in
                                LoginItem.setEnabled(on)
                            }
                        HStack {
                            Text("Updates").font(.system(size: 12))
                            Spacer()
                            Button("Check for Updates…") { UpdaterManager.shared.checkForUpdates() }
                                .controlSize(.small)
                        }
                    }

                    section("Clipboard") {
                        Toggle("Record clipboard history", isOn: $settings.clipboardEnabled)
                        Toggle("Private mode (pause capture)", isOn: $settings.privateMode)
                        Text("Items clear automatically after 24 hours unless pinned.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }

                    section("Excluded apps") {
                        Text("Copies from these apps are never recorded.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach(settings.excludedBundleIDs, id: \.self) { id in
                            HStack {
                                Text(id).font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Button {
                                    settings.excludedBundleIDs.removeAll { $0 == id }
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            TextField("com.example.app", text: $newExclude)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Button("Add") {
                                let id = newExclude.trimmingCharacters(in: .whitespaces)
                                guard !id.isEmpty, !settings.excludedBundleIDs.contains(id) else { return }
                                settings.excludedBundleIDs.append(id)
                                newExclude = ""
                            }
                        }
                    }

                    section("Floating shelf") {
                        Toggle("Shake the mouse to summon the shelf", isOn: $settings.shakeToSummon)
                            .onChange(of: settings.shakeToSummon) { _, on in
                                on ? ShakeDetector.shared.start() : ShakeDetector.shared.stop()
                            }
                        Text("Quickly wiggle the pointer left-right to pop the shelf open at the cursor.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }

                    section("Shortcuts") {
                        shortcutRow("Screenshot region", "⌘⇧7")
                        shortcutRow("Screenshot + OCR", "⌘⇧O")
                        shortcutRow("Show floating shelf", "⌘⇧S")
                        shortcutRow("Open shelf search", "⌘⇧V")
                    }

                    section("Storage") {
                        HStack {
                            Text("\(store.visibleItems.count) items on shelf")
                                .font(.system(size: 12))
                            Spacer()
                            Button("Clear all") { store.clearAll(includingPinned: true) }
                                .controlSize(.small)
                        }
                    }

                    section("Support") {
                        Text("FlowShelf is free. If it saves you time, you can buy me a coffee ☕️")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button {
                            if let url = URL(string: "https://buymeacoffee.com/mahinkadery") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            if let img = Bundle.main.loadImage("buymeacoffee") {
                                Image(nsImage: img).resizable().scaledToFit().frame(height: 46)
                            } else {
                                Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.orange))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("buymeacoffee.com/mahinkadery")
                    }

                    Text("FlowShelf \(Self.appVersion) — a smarter temporary shelf for your Mac.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
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
