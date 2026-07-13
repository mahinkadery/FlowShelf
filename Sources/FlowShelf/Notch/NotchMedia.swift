import SwiftUI

/// A small stylised audio visualiser — a few bars that undulate while playing and
/// rest low when paused. Not real FFT (macOS doesn't hand us the samples); it's a
/// phase-offset sine motion, the same trick the Dynamic Island uses.
struct AudioBars: View {
    var playing: Bool
    var color: Color = .white
    var count: Int = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(i, t))
                }
            }
            .frame(height: height, alignment: .center)
            .animation(.easeInOut(duration: 0.12), value: playing)
        }
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        guard playing else { return barWidth }          // resting dots when paused
        let phase = Double(i) * 1.7
        let s = (sin(t * 6.0 + phase) + 1) / 2           // 0…1
        let s2 = (sin(t * 9.3 + phase * 0.5) + 1) / 2
        let level = 0.35 + 0.65 * (0.6 * s + 0.4 * s2)
        return max(barWidth, height * CGFloat(level))
    }
}

/// Album artwork with a rounded frame and a graceful music-note fallback.
struct MediaArtwork: View {
    var image: NSImage?
    var side: CGFloat
    var corner: CGFloat = 6

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

/// Collapsed "live activity": album art peeking on the leading side of the notch,
/// audio bars trailing — with the physical camera-notch gap reserved in between.
struct MediaLiveActivity: View {
    @ObservedObject var media = MediaManager.shared
    var notchWidth: CGFloat
    var height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            MediaArtwork(image: media.now.artwork, side: min(height - 8, 22), corner: 5)
                .padding(.leading, 9)
            Spacer(minLength: notchWidth)          // the camera-notch gap
            AudioBars(playing: media.now.isPlaying, color: .white, height: min(height - 12, 14))
                .padding(.trailing, 13)
        }
        .frame(height: height)
    }
}

/// Expanded compact media strip: artwork, title/artist, and play/pause + next.
/// The file shelf stays the main focus below this. Left edge is aligned to the
/// same 20pt grid as the shelf tiles so the two sections line up cleanly.
struct MediaStrip: View {
    @ObservedObject var media = MediaManager.shared
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        HStack(spacing: 11) {
            MediaArtwork(image: media.now.artwork, side: 42, corner: 9)

            // Title/artist capped so the transport controls stay right next to the
            // track — not stranded at the far edge of a wide card.
            VStack(alignment: .leading, spacing: 2) {
                Text(media.now.title.isEmpty ? "Not playing" : media.now.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
                if !media.now.artist.isEmpty {
                    Text(media.now.artist)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: 190, alignment: .leading)

            HStack(spacing: 2) {
                mediaButton("backward.fill", size: 12.5) { media.previous() }
                mediaButton(media.now.isPlaying ? "pause.fill" : "play.fill", size: 16) { media.togglePlayPause() }
                mediaButton("forward.fill", size: 12.5) { media.next() }
            }

            Spacer(minLength: 6)

            outputSwitcher
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    /// Sound-output picker — switch speakers / AirPods / display audio in place.
    private var outputSwitcher: some View {
        Menu {
            ForEach(audio.devices) { device in
                Button { audio.select(device.id) } label: {
                    if device.id == audio.currentID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { audio.refresh() }
    }

    private func mediaButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
