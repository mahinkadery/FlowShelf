import SwiftUI

/// Big friendly section header used across dashboard panes — colored emblem
/// chip, bold title, one-line subtitle. The "pops to the eye" anchor.
struct PaneHeader: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: tint.opacity(0.4), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

/// One modular "emblem" setting: its own raised rounded row — icon chip,
/// title + caption, control on the right. Every setting pops individually.
struct EmblemRow<Control: View>: View {
    var icon: String
    var tint: Color
    var title: String
    var caption: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            control()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .raisedCard()
    }
}

/// The Notch section of the dashboard: everything the island does, each as a
/// modular emblem row.
struct NotchPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PaneHeader(icon: "macbook", tint: .orange, title: "Notch",
                           subtitle: "A Dynamic-Island shelf, media player and HUDs living in your notch")

                Group {
                    EmblemRow(icon: "tray.and.arrow.down.fill", tint: .orange,
                              title: "Notch shelf",
                              caption: "Tap the notch to open; drop files, images or text to shelve them") {
                        Toggle("", isOn: $settings.notchEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .onChange(of: settings.notchEnabled) { _, on in
                                on ? NotchController.shared.start() : NotchController.shared.stop()
                            }
                    }

                    EmblemRow(icon: "music.note", tint: .pink,
                              title: "Now-playing media",
                              caption: "Live activity with album art when collapsed, compact player when open") {
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
                              caption: "Sleek notch HUDs instead of Apple's centre-screen overlay") {
                        Toggle("", isOn: $settings.notchHUDEnabled).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!settings.notchEnabled)
                            .onChange(of: settings.notchHUDEnabled) { _, on in
                                on ? SystemHUDMonitor.shared.start() : SystemHUDMonitor.shared.stop()
                            }
                    }
                }
                .padding(.horizontal, 18)

                Text("On Macs without a notch, FlowShelf shows a top-centre pill instead — every feature works the same.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 20).padding(.top, 4)
            }
            .padding(.bottom, 18)
        }
    }
}
