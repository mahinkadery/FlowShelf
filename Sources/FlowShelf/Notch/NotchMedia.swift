import SwiftUI
import Combine

/// A compact audio visualiser driven by FlowShelf's live system-audio envelope,
/// with a low-rate decorative fallback when the audio tap is unavailable.
struct AudioBars: View {
    var playing: Bool
    var color: Color = .white
    /// Vibrant tint from the media's artwork; when set, the bars glow in the
    /// playing content's own color (bright top → deeper base), Dynamic-Island
    /// style, instead of plain white.
    var accent: NSColor?
    var count: Int = 6
    var barWidth: CGFloat = 2.4
    var spacing: CGFloat = 1.6
    var height: CGFloat = 14

    var body: some View {
        let totalWidth = CGFloat(count) * barWidth + CGFloat(max(0, count - 1)) * spacing
        SpectrumBarsRepresentable(playing: playing,
                                  color: NSColor(color),
                                  accent: accent,
                                  count: count,
                                  barWidth: barWidth,
                                  spacing: spacing,
                                  height: height)
        .frame(width: totalWidth, height: height)
    }
}

private struct SpectrumBarsRepresentable: NSViewRepresentable {
    let playing: Bool
    let color: NSColor
    let accent: NSColor?
    let count: Int
    let barWidth: CGFloat
    let spacing: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> SpectrumBarsView {
        SpectrumBarsView(count: count, barWidth: barWidth, spacing: spacing, height: height)
    }

    func updateNSView(_ nsView: SpectrumBarsView, context: Context) {
        nsView.update(playing: playing, color: color, accent: accent)
    }
}

private final class SpectrumBarsView: NSView {
    private let count: Int
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let maximumHeight: CGFloat
    private let gradientLayer = CAGradientLayer()
    private let barsMask = CAShapeLayer()
    private var levels: [CGFloat]
    private var playing = false
    private var fallbackTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(count: Int, barWidth: CGFloat, spacing: CGFloat, height: CGFloat) {
        self.count = count
        self.barWidth = barWidth
        self.spacing = spacing
        self.maximumHeight = height
        self.levels = Array(repeating: barWidth / height, count: count)
        super.init(frame: .zero)
        wantsLayer = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.locations = [0, 0.52, 1]
        gradientLayer.mask = barsMask
        layer?.addSublayer(gradientLayer)
        AudioSpectrum.shared.$bands
            .combineLatest(AudioSpectrum.shared.$active)
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] bands, active in self?.spectrumChanged(bands: bands, active: active) }
            .store(in: &cancellables)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    deinit { fallbackTimer?.invalidate() }

    func update(playing: Bool, color: NSColor, accent: NSColor?) {
        self.playing = playing
        updateColors(color: color, accent: accent)
        if !playing {
            stopFallback()
            setLevels(Array(repeating: barWidth / maximumHeight, count: count), animated: true)
        } else if AudioSpectrum.shared.active {
            stopFallback()
            updateLive(bands: AudioSpectrum.shared.bands)
        } else {
            startFallback()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        barsMask.frame = bounds
        CATransaction.commit()
        applyFrames(animated: false)
    }

    private func spectrumChanged(bands: [Float], active: Bool) {
        guard playing else { return }
        if active {
            stopFallback()
            updateLive(bands: bands)
        } else {
            startFallback()
        }
    }

    private func updateLive(bands: [Float]) {
        setLevels((0..<count).map { index in
            let value = index < bands.count ? bands[index] : 0
            return 0.10 + 0.90 * CGFloat(value)
        }, animated: true)
    }

    private func startFallback() {
        guard fallbackTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fallbackTick() }
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        fallbackTick()
    }

    private func stopFallback() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func fallbackTick() {
        let time = Date.timeIntervalSinceReferenceDate
        setLevels((0..<count).map { index in
            let phase = Double(index) * 1.7
            let first = (sin(time * 6.0 + phase) + 1) / 2
            let second = (sin(time * 9.3 + phase * 0.5) + 1) / 2
            return CGFloat(0.35 + 0.65 * (0.6 * first + 0.4 * second))
        }, animated: true)
    }

    private func setLevels(_ levels: [CGFloat], animated: Bool) {
        self.levels = levels
        applyFrames(animated: animated)
    }

    private func applyFrames(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let path = CGMutablePath()
        for index in 0..<count {
            let height = max(barWidth, maximumHeight * levels[index])
            let rect = CGRect(x: CGFloat(index) * (barWidth + spacing),
                              y: (bounds.height - height) / 2,
                              width: barWidth,
                              height: height)
            path.addRoundedRect(in: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2)
        }
        let previousPath = barsMask.presentation()?.path ?? barsMask.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barsMask.path = path
        CATransaction.commit()
        guard animated, let previousPath else { return }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = previousPath
        animation.toValue = path
        animation.duration = 0.11
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        barsMask.add(animation, forKey: "beatPath")
    }

    private func updateColors(color: NSColor, accent: NSColor?) {
        guard let rgb = (accent ?? color).usingColorSpace(.deviceRGB) else { return }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let saturationValue = accent == nil ? 0 : min(max(saturation, 0.48), 0.92)
        let brightnessValue = min(max(brightness, 0.72), 1)
        let left = NSColor(deviceHue: (hue + 0.95).truncatingRemainder(dividingBy: 1),
                           saturation: saturationValue, brightness: brightnessValue, alpha: alpha)
        let centre = NSColor(deviceHue: hue,
                             saturation: saturationValue, brightness: brightnessValue, alpha: alpha)
        let right = NSColor(deviceHue: (hue + 0.05).truncatingRemainder(dividingBy: 1),
                            saturation: saturationValue, brightness: brightnessValue, alpha: alpha)
        let highlight = left.blended(withFraction: 0.38, of: NSColor.white) ?? left
        let deep = right.blended(withFraction: 0.20, of: NSColor.black) ?? right
        gradientLayer.colors = [highlight.cgColor, centre.cgColor, deep.withAlphaComponent(0.84).cgColor]
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
            audio.refresh()
            NotchController.shared.pulseExpanded()
            withAnimation(FlowMotion.expandOpen) { audio.pickerOpen.toggle() }
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
