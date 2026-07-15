import SwiftUI

/// A small stylised audio visualiser — a few bars that undulate while playing and
/// rest low when paused. Not real FFT (macOS doesn't hand us the samples); it's a
/// phase-offset sine motion, the same trick the Dynamic Island uses.
struct AudioBars: View {
    var playing: Bool
    var color: Color = .white
    /// Vibrant tint from the media's artwork; when set, the bars glow in the
    /// playing content's own color (bright top → deeper base), Dynamic-Island
    /// style, instead of plain white.
    var accent: NSColor?
    var count: Int = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14

    private var fill: AnyShapeStyle {
        guard let accent else { return AnyShapeStyle(color) }
        return AnyShapeStyle(LinearGradient(
            colors: [Color(nsColor: accent.vibrant(saturation: 0.65, brightness: 1.0)),
                     Color(nsColor: accent.vibrant(saturation: 0.9, brightness: 0.75))],
            startPoint: .top, endPoint: .bottom))
    }

    @ObservedObject private var spectrum = AudioSpectrum.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(fill)
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
        let organic = 0.6 * s + 0.4 * s2                // per-bar shimmer
        if spectrum.active {
            // Real loudness drives the amplitude; the phase-offset shimmer keeps
            // each bar distinct so it reads as a spectrum, not a VU needle.
            let live = Double(spectrum.level)
            let level = 0.12 + 0.88 * live * (0.55 + 0.45 * organic)
            return max(barWidth, height * CGFloat(level))
        }
        let level = 0.35 + 0.65 * organic
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
            AudioBars(playing: media.now.isPlaying, color: .white,
                      accent: media.now.accent, height: min(height - 12, 14))
                .padding(.trailing, 13)
        }
        .frame(height: height)
    }
}

/// A title that scrolls slowly when it doesn't fit (premium mini-player feel);
/// static when it does. Restarts per track via `.id(text)` at the call site.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12.5, weight: .semibold)
    var color: Color = .white
    var gap: CGFloat = 36

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflows = textWidth > geo.size.width + 1
            HStack(spacing: gap) {
                Text(text).font(font).foregroundStyle(color).fixedSize()
                    .background(GeometryReader { t in
                        Color.clear.onAppear { textWidth = t.size.width }
                    })
                if overflows {
                    Text(text).font(font).foregroundStyle(color).fixedSize()
                }
            }
            .offset(x: overflows ? offset : 0)
            .frame(maxHeight: .infinity, alignment: .leading)
            .onChange(of: textWidth) { _, w in
                guard w > geo.size.width + 1, !FlowMotion.reduceMotion else { return }
                offset = 0
                let travel = w + gap
                withAnimation(.linear(duration: Double(travel) / 24)
                    .delay(2.0)
                    .repeatForever(autoreverses: false)) {
                    offset = -travel
                }
            }
        }
        .clipped()
    }
}

/// Expanded compact media strip: artwork, marquee title, thin progress bar, and
/// transport controls. The file shelf stays the main focus below this. Left edge
/// is aligned to the same 20pt grid as the shelf tiles.
struct MediaStrip: View {
    @ObservedObject var media = MediaManager.shared
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        // The whole player sits CENTERED in the card (art · title · controls ·
        // output), rather than scattered to the edges.
        HStack(spacing: 11) {
            Spacer(minLength: 12)

            MediaArtwork(image: media.now.artwork, side: 42, corner: 10)

            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(text: media.now.title.isEmpty ? "Not playing" : media.now.title)
                    .frame(height: 15)
                    .id(media.now.title)             // restart the scroll per track
                if !media.now.artist.isEmpty {
                    Text(media.now.artist)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1).truncationMode(.tail)
                }
                progressBar
            }
            .frame(maxWidth: 190, alignment: .leading)

            HStack(spacing: 2) {
                mediaButton("backward.fill", size: 12.5) { media.previous() }
                mediaButton(media.now.isPlaying ? "pause.fill" : "play.fill", size: 16) { media.togglePlayPause() }
                mediaButton("forward.fill", size: 12.5) { media.next() }
            }

            outputSwitcher

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    /// While the user is scrubbing, this overrides the live position.
    @State private var scrubFraction: Double?

    /// Thin elapsed/duration line (the iPhone-player staple) — click or drag
    /// anywhere on it to seek. Ticks twice a second between the adapter's
    /// sparse updates.
    @ViewBuilder private var progressBar: some View {
        if media.now.duration > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                GeometryReader { geo in
                    let f = scrubFraction ?? max(0, min(1, media.now.currentPosition / media.now.duration))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(scrubFraction != nil ? 1 : 0.85))
                            .frame(width: max(2, geo.size.width * f))
                    }
                    .frame(maxHeight: .infinity)
                    // Generous hit area around the hairline bar.
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrubFraction = max(0, min(1, v.location.x / geo.size.width))
                            }
                            .onEnded { v in
                                let f = max(0, min(1, v.location.x / geo.size.width))
                                media.seek(to: f * media.now.duration)
                                scrubFraction = nil
                            }
                    )
                }
                .frame(height: 4)
            }
        }
    }

    /// Sound-output toggle — opens the iOS-style device panel BESIDE the notch
    /// (OutputPickerController), anchored to this button's screen position.
    @State private var anchorFrame: NSRect = .zero

    private var outputSwitcher: some View {
        Button {
            OutputPickerController.shared.toggle(near: anchorFrame)
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(audio.pickerOpen ? Color.black : .white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white).opacity(audio.pickerOpen ? 0.9 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .interactiveGlassCircle()
        .background(ScreenFrameReader { anchorFrame = $0 })
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
        .interactiveGlassCircle()
    }
}


/// Reports the hosting view's SCREEN frame (for anchoring panels beside it).
struct ScreenFrameReader: NSViewRepresentable {
    var onChange: (NSRect) -> Void

    final class Reporter: NSView {
        var onChange: ((NSRect) -> Void)?
        override func layout() {
            super.layout()
            report()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }
        private func report() {
            guard let window else { return }
            onChange?(window.convertToScreen(convert(bounds, to: nil)))
        }
    }

    func makeNSView(context: Context) -> Reporter {
        let v = Reporter(); v.onChange = onChange; return v
    }
    func updateNSView(_ nsView: Reporter, context: Context) { nsView.onChange = onChange }
}

extension NSColor {
    /// A vibrancy-boosted variant: same hue, saturation/brightness lifted into a
    /// glowing range — grey-ish album art still yields a lively tint.
    func vibrant(saturation minSat: CGFloat, brightness minBri: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Near-greyscale art has no meaningful hue — keep it white-ish instead of
        // inventing a random color.
        if s < 0.08 { return NSColor(white: max(b, 0.85), alpha: 1) }
        return NSColor(hue: h, saturation: max(s, minSat),
                       brightness: max(b, minBri), alpha: 1)
    }
}
