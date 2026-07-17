import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    let onFinish: (OnboardingDestination) -> Void

    private let pages = OnboardingPage.allCases

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)

            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    if page == index {
                        pageContent(item)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider().opacity(0.45)
            footer
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.18)
                RadialGradient(
                    colors: [pages[page].tint.opacity(0.18), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 650
                )
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 9) {
            FlowShelfGlyph(size: 23, color: .accentColor)
            Text("Welcome to FlowShelf")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("SETUP")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(1.3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 13)
    }

    private func pageContent(_ item: OnboardingPage) -> some View {
        HStack(spacing: 42) {
            VStack(alignment: .leading, spacing: 18) {
                EmblemChip(icon: item.symbol, tint: item.tint, size: 43, iconSize: 19)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(1.1)
                        .foregroundStyle(item.tint)
                    Text(item.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item == .permissions {
                    Button("Review permission health") {
                        onFinish(.permissions)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Spacer()
            }
            .frame(width: 310, alignment: .leading)

            OnboardingArt(page: item)
                .id(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 38)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? pages[page].tint : Color.primary.opacity(0.14))
                        .frame(width: index == page ? 24 : 7, height: 7)
                        .animation(FlowMotion.state, value: page)
                }
            }

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
        .padding(.vertical, 16)
    }

    private func move(to newPage: Int) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : FlowMotion.transition) {
            page = newPage
        }
    }
}

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case shelf, notch, shortcuts, permissions
    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .shelf: return "Collect"
        case .notch: return "Stay in flow"
        case .shortcuts: return "Move faster"
        case .permissions: return "You stay in control"
        }
    }
    var title: String {
        switch self {
        case .shelf: return "One shelf for everything."
        case .notch: return "Your notch becomes useful."
        case .shortcuts: return "Work at keyboard speed."
        case .permissions: return "Only grant what you need."
        }
    }
    var detail: String {
        switch self {
        case .shelf:
            return "Copies, screenshots, files, links, and reusable snippets land in one temporary shelf. Pin what matters; the rest can clean itself up."
        case .notch:
            return "Drop items into the notch, control media, and see quiet system HUDs without leaving the app you are working in."
        case .shortcuts:
            return "Every global shortcut can be changed. Open the shelf, search, capture, snap windows, or switch apps with combinations that fit your hands."
        case .permissions:
            return "FlowShelf stays on your Mac and asks for system access only when a feature needs it. You can inspect every permission from one dashboard page."
        }
    }
    var symbol: String {
        switch self {
        case .shelf: return "tray.full.fill"
        case .notch: return "macbook"
        case .shortcuts: return "keyboard.fill"
        case .permissions: return "checkmark.shield.fill"
        }
    }
    var tint: Color {
        switch self {
        case .shelf: return .orange
        case .notch: return .pink
        case .shortcuts: return .blue
        case .permissions: return .teal
        }
    }
}

private struct OnboardingArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: OnboardingPage
    @State private var animated = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.32), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
            page.tint.opacity(0.13).blur(radius: 48).padding(38)

            switch page {
            case .shelf: shelfArt
            case .notch: notchArt
            case .shortcuts: shortcutsArt
            case .permissions: permissionsArt
            }
        }
        .frame(width: 390, height: 370)
        .shadow(color: page.tint.opacity(0.2), radius: 24, y: 14)
        .onAppear {
            guard !reduceMotion else { animated = true; return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                animated = true
            }
        }
    }

    private var shelfArt: some View {
        ZStack {
            SVGImage(image: OnboardingSVG.shelf)
                .frame(width: 300, height: 160)
                .offset(y: 72)

            SVGImage(image: OnboardingSVG.document)
                .frame(width: 88, height: 104)
                .rotationEffect(.degrees(animated ? -4 : -12))
                .offset(x: animated ? -103 : -145, y: animated ? -35 : -95)
            SVGImage(image: OnboardingSVG.imageCard)
                .frame(width: 88, height: 104)
                .rotationEffect(.degrees(animated ? 3 : 11))
                .offset(x: animated ? 0 : 18, y: animated ? -52 : -112)
            SVGImage(image: OnboardingSVG.linkCard)
                .frame(width: 88, height: 104)
                .rotationEffect(.degrees(animated ? 5 : 14))
                .offset(x: animated ? 103 : 145, y: animated ? -28 : -92)
        }
    }

    private var notchArt: some View {
        ZStack {
            SVGImage(image: OnboardingSVG.display)
                .frame(width: 330, height: 238)
                .offset(y: 22)
            SVGImage(image: OnboardingSVG.notch)
                .frame(width: animated ? 248 : 204, height: animated ? 104 : 74)
                .offset(y: animated ? -69 : -82)
            Circle()
                .fill(.pink.opacity(0.85))
                .frame(width: 18, height: 18)
                .blur(radius: animated ? 7 : 2)
                .offset(x: animated ? 92 : -70, y: -91)
        }
    }

    private var shortcutsArt: some View {
        ZStack {
            SVGImage(image: OnboardingSVG.keyboard)
                .frame(width: 320, height: 214)
                .rotation3DEffect(.degrees(animated ? 4 : 10), axis: (x: 1, y: 0, z: 0))
            HStack(spacing: 12) {
                KeyCap(symbol: "⌘", tint: .blue)
                KeyCap(symbol: "⇧", tint: .blue)
                KeyCap(symbol: "S", tint: .blue)
            }
            .scaleEffect(animated ? 1.15 : 0.95)
            .offset(y: -18)
            .shadow(color: .blue.opacity(0.35), radius: animated ? 16 : 5)
        }
    }

    private var permissionsArt: some View {
        ZStack {
            SVGImage(image: OnboardingSVG.shield)
                .frame(width: 180, height: 210)
                .scaleEffect(animated ? 1.05 : 0.94)
                .shadow(color: .teal.opacity(0.3), radius: animated ? 22 : 8)
            permissionOrb("figure.wave", color: .blue, angle: -42)
            permissionOrb("rectangle.inset.filled.and.person.filled", color: .purple, angle: 42)
            permissionOrb("keyboard.badge.eye", color: .orange, angle: 180)
        }
    }

    private func permissionOrb(_ symbol: String, color: Color, angle: Double) -> some View {
        let radians = angle * .pi / 180
        let radius: CGFloat = animated ? 133 : 112
        return ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(color.opacity(0.55), lineWidth: 1)
            Image(systemName: symbol).foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
        .offset(x: CGFloat(cos(radians)) * radius, y: CGFloat(sin(radians)) * radius)
    }
}

private struct SVGImage: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

private enum OnboardingSVG {
    static let shelf = decode("""
    <svg xmlns="http://www.w3.org/2000/svg" width="600" height="300" viewBox="0 0 600 300"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#ffb32e"/><stop offset="1" stop-color="#d76500"/></linearGradient></defs><rect x="40" y="66" width="520" height="190" rx="42" fill="#121212" fill-opacity=".88" stroke="#fff" stroke-opacity=".22" stroke-width="3"/><path d="M80 106h440v102c0 18-14 32-32 32H112c-18 0-32-14-32-32z" fill="url(#g)" fill-opacity=".2"/><path d="M190 144h220" stroke="#ffad22" stroke-width="8" stroke-linecap="round"/><circle cx="113" cy="99" r="9" fill="#ff5f57"/><circle cx="141" cy="99" r="9" fill="#febc2e"/><circle cx="169" cy="99" r="9" fill="#28c840"/></svg>
    """)
    static let document = decode(cardSVG(color: "#ff9f0a", glyph: "M40 30h40l22 22v68H40z M80 30v24h22 M55 76h32 M55 92h32"))
    static let imageCard = decode(cardSVG(color: "#bf5af2", glyph: "M40 36h62v78H40z M46 101l18-22 13 14 9-10 10 18 M57 58a7 7 0 1 0 0-14 7 7 0 0 0 0 14"))
    static let linkCard = decode(cardSVG(color: "#0a84ff", glyph: "M57 88l-8 8a17 17 0 0 1-24-24l14-14a17 17 0 0 1 24 0 M85 62l8-8a17 17 0 0 1 24 24l-14 14a17 17 0 0 1-24 0 M55 82l34-34"))
    static let display = decode("""
    <svg xmlns="http://www.w3.org/2000/svg" width="700" height="500" viewBox="0 0 700 500"><defs><linearGradient id="s" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#1a1c24"/><stop offset="1" stop-color="#050506"/></linearGradient></defs><rect x="45" y="30" width="610" height="390" rx="36" fill="#0b0b0d" stroke="#fff" stroke-opacity=".3" stroke-width="5"/><rect x="67" y="53" width="566" height="344" rx="17" fill="url(#s)"/><path d="M12 426h676l-54 38H66z" fill="#b7bac2" fill-opacity=".58"/><path d="M280 426h140l-18 13H298z" fill="#08080a" fill-opacity=".75"/></svg>
    """)
    static let notch = decode("""
    <svg xmlns="http://www.w3.org/2000/svg" width="500" height="210" viewBox="0 0 500 210"><defs><linearGradient id="n" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#101012"/><stop offset=".65" stop-color="#17171a" stop-opacity=".92"/><stop offset="1" stop-color="#fff" stop-opacity=".14"/></linearGradient></defs><path d="M0 0h500v92c0 65-30 112-96 112H96C30 204 0 157 0 92z" fill="url(#n)" stroke="#fff" stroke-opacity=".3" stroke-width="3"/><rect x="76" y="53" width="348" height="64" rx="23" fill="#fff" fill-opacity=".075" stroke="#fff" stroke-opacity=".16"/><circle cx="115" cy="85" r="17" fill="#ff375f"/><path d="M153 76h152M153 96h108" stroke="#fff" stroke-opacity=".72" stroke-width="10" stroke-linecap="round"/><circle cx="381" cy="85" r="21" fill="#fff" fill-opacity=".1"/><path d="M375 75l18 10-18 10z" fill="#fff" fill-opacity=".85"/></svg>
    """)
    static let keyboard = decode("""
    <svg xmlns="http://www.w3.org/2000/svg" width="700" height="450" viewBox="0 0 700 450"><defs><linearGradient id="k" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#454956"/><stop offset="1" stop-color="#17181d"/></linearGradient></defs><rect x="35" y="45" width="630" height="350" rx="38" fill="url(#k)" stroke="#fff" stroke-opacity=".3" stroke-width="4"/><g fill="#111217" stroke="#fff" stroke-opacity=".16" stroke-width="2"><rect x="72" y="82" width="72" height="62" rx="12"/><rect x="160" y="82" width="72" height="62" rx="12"/><rect x="248" y="82" width="72" height="62" rx="12"/><rect x="336" y="82" width="72" height="62" rx="12"/><rect x="424" y="82" width="72" height="62" rx="12"/><rect x="512" y="82" width="110" height="62" rx="12"/><rect x="72" y="160" width="92" height="62" rx="12"/><rect x="180" y="160" width="72" height="62" rx="12"/><rect x="268" y="160" width="72" height="62" rx="12"/><rect x="356" y="160" width="72" height="62" rx="12"/><rect x="444" y="160" width="72" height="62" rx="12"/><rect x="532" y="160" width="90" height="62" rx="12"/><rect x="72" y="238" width="112" height="62" rx="12"/><rect x="200" y="238" width="72" height="62" rx="12"/><rect x="288" y="238" width="72" height="62" rx="12"/><rect x="376" y="238" width="72" height="62" rx="12"/><rect x="464" y="238" width="158" height="62" rx="12"/><rect x="72" y="316" width="158" height="46" rx="11"/><rect x="246" y="316" width="280" height="46" rx="11"/><rect x="542" y="316" width="80" height="46" rx="11"/></g></svg>
    """)
    static let shield = decode("""
    <svg xmlns="http://www.w3.org/2000/svg" width="360" height="420" viewBox="0 0 360 420"><defs><linearGradient id="a" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#64d2ff"/><stop offset="1" stop-color="#00a58b"/></linearGradient></defs><path d="M180 20c51 36 101 48 148 54v116c0 96-56 167-148 207C88 357 32 286 32 190V74c47-6 97-18 148-54z" fill="url(#a)" fill-opacity=".86" stroke="#fff" stroke-opacity=".58" stroke-width="6"/><path d="M113 202l43 43 94-104" fill="none" stroke="#fff" stroke-width="28" stroke-linecap="round" stroke-linejoin="round"/></svg>
    """)

    private static func cardSVG(color: String, glyph: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="140" height="170" viewBox="0 0 140 170"><defs><linearGradient id="c" x1="0" y1="0" x2="1" y2="1"><stop stop-color="\(color)"/><stop offset="1" stop-color="#111"/></linearGradient></defs><rect x="4" y="4" width="132" height="162" rx="28" fill="url(#c)" stroke="#fff" stroke-opacity=".42" stroke-width="3"/><path d="\(glyph)" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>
        """
    }

    private static func decode(_ source: String) -> NSImage {
        NSImage(data: Data(source.utf8)) ?? NSImage(size: NSSize(width: 1, height: 1))
    }
}
