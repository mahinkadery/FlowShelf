import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var direction = 1
    let onFinish: (OnboardingDestination) -> Void

    private let pages = OnboardingPage.allCases

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    if page == index {
                        pageContent(item)
                            .id(item)
                            .transition(pageTransition)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider().opacity(0.4)
            footer
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.18)
                RadialGradient(
                    colors: [pages[page].tint.opacity(0.19), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 680
                )
                RadialGradient(
                    colors: [pages[page].tint.opacity(0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: page)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
            Text("Welcome to FlowShelf")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("\(page + 1) OF \(pages.count)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .kerning(1.1)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 22)
        .padding(.top, 17)
        .padding(.bottom, 13)
    }

    private func pageContent(_ item: OnboardingPage) -> some View {
        HStack(alignment: .top, spacing: 44) {
            VStack(alignment: .leading, spacing: 17) {
                OnboardingFeatureEmblem(page: item)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(1.15)
                        .foregroundStyle(item.tint)
                    Text(item.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .font(.system(size: 14.2))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                            .tint(item.tint)
                    }
                }

                if item == .privacy {
                    Button("Review permission health") {
                        onFinish(.permissions)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 315, alignment: .leading)

            OnboardingArt(page: item)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 31)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Button {
                        move(to: index)
                    } label: {
                        Capsule()
                            .fill(index == page ? pages[page].tint : Color.primary.opacity(0.14))
                            .frame(width: index == page ? 25 : 7, height: 7)
                    }
                    .buttonStyle(.plain)
                    .help(pages[index].shortLabel)
                    .accessibilityLabel("Go to \(pages[index].shortLabel)")
                    .animation(FlowMotion.state, value: page)
                }
            }

            Text(pages[page].shortLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 7)
                .contentTransition(.opacity)

            Spacer()

            if page > 0 {
                Button("Back") { move(to: page - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Button("Skip") { onFinish(.none) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Button(page == pages.count - 1 ? "Open FlowShelf" : "Continue") {
                if page == pages.count - 1 {
                    onFinish(.shelf)
                } else {
                    move(to: page + 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let sign = CGFloat(direction >= 0 ? 1 : -1)
        return .asymmetric(
            insertion: .modifier(
                active: OnboardingPageMotion(offset: 76 * sign, angle: -7 * Double(sign), opacity: 0, blur: 8),
                identity: OnboardingPageMotion(offset: 0, angle: 0, opacity: 1, blur: 0)
            ),
            removal: .modifier(
                active: OnboardingPageMotion(offset: -56 * sign, angle: 5 * Double(sign), opacity: 0, blur: 5),
                identity: OnboardingPageMotion(offset: 0, angle: 0, opacity: 1, blur: 0)
            )
        )
    }

    private func move(to newPage: Int) {
        guard pages.indices.contains(newPage), newPage != page else { return }
        direction = newPage > page ? 1 : -1
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : FlowMotion.transition) {
            page = newPage
        }
    }
}

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, shelf, notch, capture, windows, intelligence, privacy
    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .welcome: return "Welcome"
        case .shelf: return "Shelf"
        case .notch: return "Notch"
        case .capture: return "Capture"
        case .windows: return "Window tools"
        case .intelligence: return "Snippets & AI"
        case .privacy: return "Privacy & Cleaner"
        }
    }

    var eyebrow: String {
        switch self {
        case .welcome: return "Welcome to FlowShelf"
        case .shelf: return "Collect anything"
        case .notch: return "Stay in flow"
        case .capture: return "Capture and explain"
        case .windows: return "Own your workspace"
        case .intelligence: return "Reuse and understand"
        case .privacy: return "Private by design"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Everything temporary finally has a home."
        case .shelf: return "One shelf for everything."
        case .notch: return "Your notch becomes useful."
        case .capture: return "Screenshots that do more."
        case .windows: return "Every window, exactly where you want it."
        case .intelligence: return "Write less. Find more."
        case .privacy: return "Powerful without giving up control."
        }
    }

    var detail: String {
        switch self {
        case .welcome:
            return "FlowShelf catches what you copy, drop, and capture — and keeps it ready until you need it. This short tour shows the highlights; everything runs free and fully on your Mac."
        case .shelf:
            return "Copies, files, links, images, and screenshots arrive in one temporary shelf. Search instantly, pin the important things, and let the rest clear itself."
        case .notch:
            return "Drop items into the notch, control media, and see quiet volume, brightness, charging, and battery HUDs without leaving your current app."
        case .capture:
            return "Capture a region or window, extract text with OCR, scan QR codes, pin images, and annotate with arrows, highlights, blur, crop, text, and numbered steps."
        case .windows:
            return "Preview windows from the Dock, switch with thumbnails, and snap focused windows into halves, quarters, maximize, or center using your own shortcuts."
        case .intelligence:
            return "Save reusable snippets and use Apple Intelligence on-device to title, search, summarize, clean up, and answer questions from your shelf."
        case .privacy:
            return "Clipboard history stays on your Mac. Private Mode pauses capture instantly, permissions follow enabled features, and Cleaner reveals app leftovers before removal."
        }
    }

    var highlights: [String] {
        switch self {
        case .welcome: return ["Free, notarized, no account", "100% on-device — nothing leaves your Mac", "Two-minute tour, skip any time"]
        case .shelf: return ["24-hour or permanent history", "Search, pin, drag and paste", "Floating shelf at your cursor"]
        case .notch: return ["Drop shelf on every display", "Now-playing media controls", "Optional system HUDs"]
        case .capture: return ["Region, window and OCR capture", "Professional annotation tools", "Pin, QR scan and image tools"]
        case .windows: return ["Dock hover previews", "Thumbnail window switcher", "Customizable snap shortcuts"]
        case .intelligence: return ["Reusable text snippets", "Smart search and auto-titles", "Fully on-device AI actions"]
        case .privacy: return ["Private Mode and excluded apps", "Feature-aware permissions", "App cleaner with leftover review"]
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .shelf: return "tray.full.fill"
        case .notch: return "macbook"
        case .capture: return "camera.viewfinder"
        case .windows: return "rectangle.stack.fill"
        case .intelligence: return "sparkles"
        case .privacy: return "checkmark.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: return .yellow
        case .shelf: return .orange
        case .notch: return .pink
        case .capture: return .purple
        case .windows: return .blue
        case .intelligence: return .indigo
        case .privacy: return .teal
        }
    }
}

private struct OnboardingPageMotion: ViewModifier {
    let offset: CGFloat
    let angle: Double
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: offset)
            .scaleEffect(opacity == 1 ? 1 : 0.965)
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: offset >= 0 ? .leading : .trailing,
                perspective: 0.72
            )
            .blur(radius: blur)
    }
}

private struct OnboardingFeatureEmblem: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            Circle()
                .stroke(page.tint.opacity(0.18), lineWidth: 1)
                .frame(width: 58, height: 58)
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    AngularGradient(colors: [.clear, page.tint.opacity(0.85), .clear], center: .center),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(Double(page.rawValue * 38) - 55))
                .frame(width: 54, height: 54)
            EmblemChip(icon: page.symbol, tint: page.tint, size: 44, iconSize: 19)
                .shadow(color: page.tint.opacity(0.34), radius: 12, y: 5)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
                .shadow(color: page.tint, radius: 5)
                .offset(x: 24, y: -10)
        }
        .frame(width: 58, height: 58)
    }
}

private struct MotionBackdrop: View {
    let tint: Color
    let phase: Int

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.06, to: phase >= 2 ? 0.78 : 0.18)
                .stroke(tint.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 8]))
                .frame(width: 320, height: 320)
                .rotationEffect(.degrees(phase >= 3 ? 24 : -14))
            Circle()
                .trim(from: 0.32, to: phase >= 3 ? 0.94 : 0.48)
                .stroke(.white.opacity(0.07), lineWidth: 1)
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(phase >= 3 ? -32 : 12))
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(0.38 - Double(index) * 0.08))
                    .frame(width: CGFloat(5 + index * 2), height: CGFloat(5 + index * 2))
                    .offset(
                        x: phase >= 3 ? CGFloat([138, -112, 86][index]) : 0,
                        y: phase >= 3 ? CGFloat([-82, 104, 128][index]) : 0
                    )
                    .opacity(phase >= 2 ? 1 : 0)
            }
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.88), value: phase)
        .allowsHitTesting(false)
    }
}

private struct DemoCursor: View {
    let tint: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cursorarrow")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .padding(.horizontal, 7)
                .frame(height: 21)
                .background(Capsule().fill(tint.gradient))
                .foregroundStyle(.white)
        }
    }
}

private struct DrawnArrow: View {
    let progress: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: 71))
            path.addCurve(
                to: CGPoint(x: 72, y: 18),
                control1: CGPoint(x: 31, y: 73),
                control2: CGPoint(x: 61, y: 49)
            )
            path.move(to: CGPoint(x: 48, y: 19))
            path.addLine(to: CGPoint(x: 72, y: 18))
            path.addLine(to: CGPoint(x: 67, y: 42))
        }
        .trim(from: 0, to: progress)
        .stroke(
            LinearGradient(colors: [.pink, .orange], startPoint: .bottomLeading, endPoint: .topTrailing),
            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 82, height: 82)
        .shadow(color: .pink.opacity(0.42), radius: 8)
    }
}

private struct TypingDots: View {
    let phase: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.indigo.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase >= index + 2 ? 1 : 0.45)
                    .opacity(phase >= index + 2 ? 1 : 0.25)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.indigo.opacity(0.12)))
    }
}

private struct OnboardingArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: OnboardingPage
    @State private var phase = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            Circle()
                .fill(page.tint.opacity(0.2))
                .frame(width: 260, height: 260)
                .blur(radius: 62)
                .offset(x: 110, y: -105)

            MotionBackdrop(tint: page.tint, phase: phase)

            scene
                .frame(width: 360, height: 300)
                .padding(22)

            LinearGradient(
                colors: [.clear, .white.opacity(0.03), .white.opacity(0.24), .white.opacity(0.03), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 120, height: 540)
            .rotationEffect(.degrees(18))
            .offset(x: phase >= 5 ? 330 : -330)
            .opacity(phase == 4 ? 0.8 : 0)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
        .frame(width: 420, height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: page.tint.opacity(0.2), radius: 24, y: 14)
        .task(id: page) {
            phase = 0
            if reduceMotion {
                phase = 5
                return
            }
            await advance(to: 1, after: 70)
            await advance(to: 2, after: 190)
            await advance(to: 3, after: 230)
            await advance(to: 4, after: 260)
            await advance(to: 5, after: 420)
        }
    }

    @ViewBuilder private var scene: some View {
        switch page {
        case .welcome: WelcomeDemo(phase: phase, reduceMotion: reduceMotion)
        case .shelf: ShelfDemo(phase: phase, reduceMotion: reduceMotion)
        case .notch: NotchDemo(phase: phase, reduceMotion: reduceMotion)
        case .capture: CaptureDemo(phase: phase, reduceMotion: reduceMotion)
        case .windows: WindowsDemo(phase: phase, reduceMotion: reduceMotion)
        case .intelligence: IntelligenceDemo(phase: phase, reduceMotion: reduceMotion)
        case .privacy: PrivacyDemo(phase: phase, reduceMotion: reduceMotion)
        }
    }

    @MainActor private func advance(to next: Int, after milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.84)) {
            phase = next
        }
    }
}

/// The welcome page's hero: the FlowShelf organizer-tray artwork settling in
/// with a soft drop, then floating gently. Artwork lives in WelcomeTile.png
/// (rendered from svg-assets/image-organizer-icon.svg).
private struct WelcomeDemo: View {
    let phase: Int
    let reduceMotion: Bool
    @State private var floating = false

    var body: some View {
        ZStack {
            if let tile = Bundle.main.loadImage("WelcomeTile") {
                Image(nsImage: tile)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 285)
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 16)
                    .scaleEffect(phase >= 1 ? 1 : 0.86)
                    .opacity(phase >= 1 ? 1 : 0)
                    .offset(y: floating ? -6 : 4)
                    .rotation3DEffect(.degrees(floating ? 1.6 : -1.2), axis: (x: 1, y: 0, z: 0))
            } else {
                // Artwork missing from the bundle — fall back to the app icon.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 200)
                    .opacity(phase >= 1 ? 1 : 0)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

private struct DemoWindow<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let content: Content

    init(title: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Circle().fill(.yellow).frame(width: 7, height: 7)
                Circle().fill(.green).frame(width: 7, height: 7)
                Spacer()
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle().fill(tint.opacity(0.35)).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            Divider().opacity(0.35)
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 16, y: 9)
    }
}

private struct ShelfDemo: View {
    let phase: Int
    let reduceMotion: Bool

    private let items: [(String, Color, String, String)] = [
        ("doc.text.fill", .orange, "Launch notes", "Copied from Notes"),
        ("photo.fill", .purple, "Screenshot", "Captured just now"),
        ("link", .blue, "flowshelf.app", "Link from Safari"),
    ]

    var body: some View {
        ZStack {
            DemoWindow(title: "Today’s Shelf", tint: .orange) {
                VStack(spacing: 9) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text("Search today’s shelf…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("3 items")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045)))

                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            EmblemChip(icon: item.0, tint: item.1, size: 30, iconSize: 13)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.2).font(.system(size: 11.5, weight: .semibold))
                                Text(item.3).font(.system(size: 9.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == 0, phase >= 5 {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .symbolEffect(.bounce, value: phase)
                                    .symbolEffectsRemoved(reduceMotion)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.045)))
                        .offset(y: phase >= 2 ? 0 : CGFloat(28 + index * 12))
                        .opacity(phase >= 2 ? 1 : 0)
                        .animation(
                            reduceMotion ? nil :
                                .spring(response: 0.58, dampingFraction: 0.85)
                                .delay(Double(index) * 0.07),
                            value: phase
                        )
                    }
                }
                .padding(12)
            }

            DemoCursor(tint: .orange, label: "Pin")
                .offset(x: phase >= 4 ? 119 : 154, y: phase >= 4 ? -54 : 118)
                .opacity(phase >= 3 && phase < 5 ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.82), value: phase)
        }
        .frame(width: 342, height: 274)
        .scaleEffect(phase >= 1 ? 1 : 0.93)
        .opacity(phase >= 1 ? 1 : 0)
    }
}

private struct NotchDemo: View {
    let phase: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.12, blue: 0.17),
                                 Color(red: 0.025, green: 0.028, blue: 0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 348, height: 260)
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 8) {
                        ForEach(["doc.fill", "photo.fill", "link"], id: \.self) { symbol in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.07))
                                .frame(width: 72, height: 56)
                                .overlay {
                                    Image(systemName: symbol).foregroundStyle(.white.opacity(0.7))
                                }
                        }
                    }
                    .padding(.bottom, 20)
                    .opacity(phase >= 5 ? 1 : 0)
                    .offset(y: phase >= 5 ? 0 : 18)
                }
                .offset(y: 38)
                .scaleEffect(phase >= 1 ? 1 : 0.96)
                .opacity(phase >= 1 ? 1 : 0)

            VStack(spacing: 9) {
                Capsule().fill(.black).frame(width: 96, height: 25)

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [.pink, .purple],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .overlay { Image(systemName: "music.note").foregroundStyle(.white) }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Now Playing").font(.system(size: 11.5, weight: .semibold))
                        Text("On-device media controls")
                            .font(.system(size: 9.3)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 29, height: 29)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .padding(.horizontal, 15)
                .opacity(phase >= 2 ? 1 : 0)
            }
            .padding(.bottom, 14)
            .frame(width: phase >= 2 ? 272 : 118, height: phase >= 2 ? 102 : 31,
                   alignment: .top)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0
                )
                .fill(.black.opacity(0.96))
            )
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .white.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 24,
                            bottomTrailingRadius: 24,
                            topTrailingRadius: 0
                        )
                    )
            }
            .shadow(color: .pink.opacity(phase >= 2 ? 0.22 : 0), radius: 18, y: 7)

            HStack(spacing: 7) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.pink)
                Text("Launch notes.pdf")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(.regularMaterial))
            .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1) }
            .offset(x: phase >= 4 ? 0 : -118, y: phase >= 4 ? 34 : 132)
            .scaleEffect(phase >= 5 ? 0.35 : 1)
            .opacity(phase >= 3 && phase < 5 ? 1 : 0)
            .shadow(color: .pink.opacity(0.25), radius: 10, y: 5)

            Label("Drop to Shelf", systemImage: "arrow.up")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 31)
                .background(Capsule().fill(.regularMaterial))
                .offset(y: phase >= 4 ? 184 : 260)
                .opacity(phase >= 4 ? 1 : 0)
        }
        .frame(width: 360, height: 300, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.76, dampingFraction: 0.84),
                   value: phase)
    }
}

private struct CaptureDemo: View {
    let phase: Int
    let reduceMotion: Bool

    private let tools = ["arrow.up.right", "rectangle", "highlighter", "drop.halffull",
                         "textformat", "crop"]

    var body: some View {
        DemoWindow(title: "Screenshot Editor", tint: .purple) {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.18),
                             Color.orange.opacity(0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(.white.opacity(0.24)).frame(width: 150, height: 8)
                    Capsule().fill(.white.opacity(0.13)).frame(width: 220, height: 6)
                    Capsule().fill(.white.opacity(0.13)).frame(width: 188, height: 6)
                    Spacer()
                }
                .padding(28)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [7, 4]))
                    .frame(width: phase >= 2 ? 244 : 80, height: phase >= 2 ? 150 : 50)
                    .overlay(alignment: .topTrailing) {
                        Text("1240 × 760")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7).frame(height: 22)
                            .background(Capsule().fill(.black.opacity(0.62)))
                            .offset(y: -29)
                            .opacity(phase >= 2 ? 1 : 0)
                    }

                LinearGradient(
                    colors: [.clear, .white.opacity(0.85), .purple.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 5, height: 142)
                .blur(radius: 1)
                .offset(x: phase >= 4 ? 116 : -116)
                .opacity((phase == 3 || phase == 4) ? 1 : 0)

                DrawnArrow(progress: phase >= 5 ? 1 : 0)
                    .rotationEffect(.degrees(-8))
                    .offset(x: 38, y: -7)
                    .opacity(phase >= 5 ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.46), value: phase)

                HStack(spacing: 8) {
                    ForEach(tools, id: \.self) { tool in
                        Image(systemName: tool)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tool == "arrow.up.right"
                                          ? Color.purple.opacity(0.28)
                                          : Color.white.opacity(0.07))
                            )
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 44)
                .background(Capsule().fill(.black.opacity(0.68)))
                .offset(y: 102)
                .opacity(phase >= 2 ? 1 : 0)
            }
        }
        .frame(width: 350, height: 282)
        .scaleEffect(phase >= 1 ? 1 : 0.94)
        .opacity(phase >= 1 ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.84),
                   value: phase)
    }
}

private struct WindowsDemo: View {
    let phase: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.72))
                .frame(width: 350, height: 265)
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }

            ZStack {
                Rectangle()
                    .fill(.blue.opacity(0.18))
                    .frame(width: 1, height: 226)
                Rectangle()
                    .fill(.blue.opacity(0.18))
                    .frame(width: 312, height: 1)
            }
            .opacity(phase >= 2 && phase < 5 ? 1 : 0)
            .scaleEffect(phase >= 3 ? 1 : 0.65)

            WindowCard(title: "Safari", color: .blue, symbol: "safari.fill")
                .frame(width: phase >= 4 ? 150 : 215, height: phase >= 4 ? 180 : 150)
                .offset(x: phase >= 4 ? -82 : -25, y: phase >= 4 ? -17 : -28)
                .rotationEffect(.degrees(phase >= 4 ? 0 : -5))

            WindowCard(title: "Notes", color: .yellow, symbol: "note.text")
                .frame(width: phase >= 4 ? 150 : 215, height: phase >= 4 ? 180 : 150)
                .offset(x: phase >= 4 ? 82 : 28, y: phase >= 4 ? -17 : 20)
                .rotationEffect(.degrees(phase >= 4 ? 0 : 4))

            HStack(spacing: 9) {
                ForEach([("safari.fill", Color.blue), ("note.text", Color.yellow),
                         ("folder.fill", Color.cyan)], id: \.0) { app in
                    EmblemChip(icon: app.0, tint: app.1, size: 33, iconSize: 14)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 49)
            .background(Capsule().fill(.regularMaterial))
            .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1) }
            .offset(y: phase >= 5 ? 111 : 155)
            .opacity(phase >= 5 ? 1 : 0)
            .shadow(color: .blue.opacity(0.2), radius: 12, y: 7)

            Label("Dock preview", systemImage: "rectangle.on.rectangle")
                .font(.system(size: 9.5, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(Capsule().fill(.blue.opacity(0.22)))
                .offset(x: 104, y: 82)
                .opacity(phase >= 5 ? 1 : 0)
        }
        .scaleEffect(phase >= 1 ? 1 : 0.93)
        .opacity(phase >= 1 ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.82),
                   value: phase)
    }
}

private struct WindowCard: View {
    let title: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.system(size: 9.5, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 27)
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(color.opacity(0.26)).frame(width: 68, height: 7)
                Capsule().fill(.white.opacity(0.12)).frame(maxWidth: .infinity).frame(height: 6)
                Capsule().fill(.white.opacity(0.08)).frame(width: 78, height: 6)
                Spacer()
            }
            .padding(11)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.11)))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
    }
}

private struct IntelligenceDemo: View {
    let phase: Int
    let reduceMotion: Bool

    var body: some View {
        DemoWindow(title: "Snippets & AI", tint: .indigo) {
            HStack(spacing: 0) {
                VStack(spacing: 7) {
                    snippet("Customer reply", icon: "text.bubble.fill", selected: phase >= 2)
                    snippet("Meeting link", icon: "video.fill", selected: false)
                    snippet("Shipping update", icon: "shippingbox.fill", selected: false)
                    Spacer()
                }
                .padding(10)
                .frame(width: 137)
                .background(Color.primary.opacity(0.035))

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 9) {
                    Label("On-device answer", systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .symbolEffect(.pulse, value: phase)
                        .symbolEffectsRemoved(reduceMotion)
                    Text("Here’s a polished reply using your saved context:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TypingDots(phase: phase)
                        .opacity(phase >= 2 && phase < 5 ? 1 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(.white.opacity(0.18)).frame(maxWidth: .infinity).frame(height: 6)
                        Capsule().fill(.white.opacity(0.15)).frame(width: 150, height: 6)
                        Capsule().fill(.white.opacity(0.12)).frame(width: 116, height: 6)
                    }
                    .opacity(phase >= 5 ? 1 : 0)
                    .offset(y: phase >= 5 ? 0 : 12)
                    Spacer()
                    HStack {
                        Label("Private", systemImage: "lock.fill")
                        Spacer()
                        Text("Apple Intelligence")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(13)
            }
        }
        .frame(width: 352, height: 270)
        .scaleEffect(phase >= 1 ? 1 : 0.94)
        .opacity(phase >= 1 ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.68, dampingFraction: 0.84),
                   value: phase)
    }

    private func snippet(_ title: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? .indigo : .secondary)
            Text(title).font(.system(size: 9.7, weight: .medium)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.indigo.opacity(0.17) : Color.primary.opacity(0.045))
        )
    }
}

private struct PrivacyDemo: View {
    let phase: Int
    let reduceMotion: Bool

    private let permissions: [(String, String, Color)] = [
        ("Screen Recording", "Required", .purple),
        ("Accessibility", "Optional", .blue),
        ("Input Monitoring", "Optional", .orange),
    ]

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                Label("Permission Health", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(permissions.enumerated()), id: \.offset) { index, permission in
                    HStack {
                        Image(systemName: phase >= index + 2 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(permission.2)
                            .contentTransition(.symbolEffect(.replace))
                        Text(permission.0).font(.system(size: 9.7, weight: .medium))
                        Spacer()
                        Text(permission.1)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(permission.1 == "Required" ? .orange : .secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                    .offset(x: phase >= 2 ? 0 : -25)
                    .opacity(phase >= 2 ? 1 : 0)
                    .animation(
                        reduceMotion ? nil :
                            .spring(response: 0.58, dampingFraction: 0.86)
                            .delay(Double(index) * 0.06),
                        value: phase
                    )
                }

                Label("Everything stays on this Mac", systemImage: "lock.fill")
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(13)
            .frame(width: 194, height: 255)
            .background(RoundedRectangle(cornerRadius: 18).fill(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }

            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.green.opacity(0.16), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: phase >= 5 ? 0.78 : 0.08)
                        .stroke(.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(phase >= 5 ? "12" : "0")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("leftovers")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 105, height: 105)

                VStack(spacing: 4) {
                    Label("App Cleaner", systemImage: "trash.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Review every file before removal")
                        .font(.system(size: 9.2))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Label("Private Mode", systemImage: "eye.slash.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(Capsule().fill(.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                    .opacity(phase >= 4 ? 1 : 0)
                    .offset(y: phase >= 4 ? 0 : 12)
            }
            .frame(width: 145, height: 255)
            .background(RoundedRectangle(cornerRadius: 18).fill(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .scaleEffect(phase >= 1 ? 1 : 0.93)
        .opacity(phase >= 1 ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.84),
                   value: phase)
    }
}
