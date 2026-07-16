import AppKit
import SwiftUI

/// The sound-output section that lives INSIDE the notch card (no separate
/// window): when the airplay button is tapped the card itself grows sideways
/// and this column slides in — one continuous black island, like iOS.
struct OutputPickerColumn: View {
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sound Output")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(audio.devices) { device in
                        OutputRow(device: device, selected: device.id == audio.currentID) {
                            audio.select(device.id)
                            Haptics.copy()
                        }
                    }
                }
            }
            .padding(.horizontal, 6)

            // Volume of the selected device; constant height so the column
            // doesn't jump when a device has no volume control.
            Group {
                if audio.volume != nil {
                    HStack(spacing: 7) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Slider(value: Binding(get: { Double(audio.volume ?? 0) },
                                              set: { audio.setVolume(Float($0)) }), in: 0...1)
                            .controlSize(.mini)
                            .tint(.white)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                } else {
                    Text("Volume is controlled on the device")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 236)
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
            HStack(spacing: 10) {
                Image(systemName: device.icon)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 22)
                Text(device.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                ZStack {
                    Circle().fill(.white.opacity(selected ? 1 : (hovering ? 0.26 : 0.14)))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 17, height: 17)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(selected ? 0.13 : (hovering ? 0.07 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(FlowMotion.hover, value: hovering)
    }
}
