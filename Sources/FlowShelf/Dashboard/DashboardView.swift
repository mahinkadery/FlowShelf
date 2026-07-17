import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case shelf, snippets, notch, peek, clean, permissions, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shelf: return "Shelf"
        case .notch: return "Notch"
        case .snippets: return "Snippets"
        case .peek: return "Peek"
        case .clean: return "Clean"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .shelf: return "tray.full"
        case .notch: return "macbook"
        case .snippets: return "text.quote"
        case .peek: return "rectangle.on.rectangle"
        case .clean: return "trash"
        case .permissions: return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .shelf: return "Today’s items"
        case .notch: return "Island & HUDs"
        case .snippets: return "Reusable text"
        case .peek: return "Window previews"
        case .clean: return "App cleaner"
        case .permissions: return "Access health"
        case .settings: return "Preferences"
        }
    }

    /// Accent color shared by navigation and the detail backdrop.
    var tint: Color {
        switch self {
        case .shelf: return .orange
        case .notch: return Color(red: 1.0, green: 0.45, blue: 0.25)
        case .snippets: return .purple
        case .peek: return .blue
        case .clean: return .green
        case .permissions: return .teal
        case .settings: return Color(white: 0.5)
        }
    }

    /// Sidebar grouping.
    static let groups: [(title: String, items: [DashboardSection])] = [
        ("Workspace", [.shelf, .snippets]),
        ("Tools", [.notch, .peek, .clean]),
        ("App", [.permissions, .settings]),
    ]
}

/// The unified dashboard. One window, the Shelf at its heart, with Peek and
/// Clean living alongside it.
struct DashboardView: View {
    @State private var section: DashboardSection = .shelf

    init() {
        let saved = UserDefaults.standard.string(forKey: "dashboardLastSection")
        var initial = DashboardSection(rawValue: saved ?? "") ?? .shelf
        #if DEBUG
        // FLOWSHELF_SECTION=snippets|peek|clean|… opens the dashboard on that pane.
        if let raw = ProcessInfo.processInfo.environment["FLOWSHELF_SECTION"],
           let s = DashboardSection(rawValue: raw) {
            initial = s
        }
        #endif
        _section = State(initialValue: initial)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(DashboardSection.groups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            NavigationLink(value: item) {
                                HStack(spacing: 9) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .fill(LinearGradient(
                                                colors: [item.tint.opacity(0.95), item.tint.opacity(0.7)],
                                                startPoint: .top, endPoint: .bottom))
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 24, height: 24)
                                    .shadow(color: item.tint.opacity(0.35), radius: 2, y: 1)

                                    Text(item.label).font(.system(size: 13, weight: .medium))
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 7) {
                    FlowShelfGlyph(size: 18, color: .accentColor)
                    Text("FlowShelf").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.bar)
            }
        } detail: {
            ZStack {
                DashboardDetailBackdrop(tint: section.tint)

                Group {
                    switch section {
                    case .shelf:    ShelfBrowser()
                    case .notch:    NotchPane()
                    case .snippets: VStack(spacing: 0) { PaneHeader(icon: "text.quote", tint: .purple, title: "Snippets", subtitle: "Reusable text, one click to paste") ; SnippetsView() }
                    case .peek:     VStack(spacing: 0) { PaneHeader(icon: "rectangle.on.rectangle", tint: .blue, title: "Peek", subtitle: "Live window previews from your Dock") ; PeekView() }
                    case .clean:    VStack(spacing: 0) { PaneHeader(icon: "trash", tint: .green, title: "Clean", subtitle: "Uninstall apps completely, leftovers included") ; CleanView() }
                    case .permissions: PermissionHealthView()
                    case .settings: DashboardSettings()
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity,
                       alignment: .topLeading)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .onChange(of: section) { _, newSection in
            UserDefaults.standard.set(newSection.rawValue, forKey: "dashboardLastSection")
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowShelfDashboardSection)) { notification in
            guard let raw = notification.object as? String,
                  let destination = DashboardSection(rawValue: raw) else { return }
            section = destination
        }
        // ⌘1…⌘7 jump straight to a section (power-user muscle memory).
        .background {
            ForEach(Array(DashboardSection.allCases.enumerated()), id: \.element) { i, item in
                Button("") { section = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct DashboardDetailBackdrop: View {
    @ObservedObject private var glass = AccessibilityGlass.shared
    var tint: Color

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(glass.reduceTransparency ? 1 : 0.16)

            if !glass.reduceTransparency {
                RadialGradient(
                    colors: [tint.opacity(0.13), tint.opacity(0.035), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.22), value: tint)
    }
}

/// A roomier Shelf for the dashboard — same items, filter chips, search.
private struct ShelfBrowser: View {
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var filter: ShelfFilter = .today

    private var results: [ShelfItem] {
        let tokens = SearchQuery.tokens(query)
        return store.visibleItems.filter { filter.matches($0) && $0.matches(searchTokens: tokens) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shelf").font(.system(size: 19, weight: .bold))
                Text("\(store.visibleItems.count)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if AIService.isSupported && settings.aiEnabled {
                    Button { ItemActions.aiAskGeneral() } label: {
                        Label("Ask AI", systemImage: "sparkle")
                    }
                    .controlSize(.small)
                    .help("Ask anything — answers using your shelf as context")
                    if !store.visibleItems.isEmpty {
                        Button { ItemActions.aiSummarizeDay() } label: {
                            Label("Summarize day", systemImage: "sparkles")
                        }
                        .controlSize(.small)
                        .help("A friendly recap of everything you collected today")
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Search…", text: $query).textFieldStyle(.plain).frame(width: 180)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 18).padding(.vertical, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ShelfFilter.allCases) { f in
                        Button { filter = f } label: {
                            Label(f.label, systemImage: f.symbol).font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(Capsule().fill(filter == f
                                    ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                                .foregroundStyle(filter == f ? Color.accentColor : .primary)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }
            Divider()

            if results.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.14), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    Text(query.isEmpty ? "Nothing on the shelf yet" : "No matches")
                        .font(.system(size: 13, weight: .semibold))
                    Text(query.isEmpty ? "Copy something or drop a file — it lands here."
                                       : "Try fewer words, or another filter.")
                        .foregroundStyle(.secondary).font(.system(size: 11.5))
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(results) { item in
                            ShelfItemRow(item: item)
                                .onTapGesture(count: 2) { ItemActions.open(item) }
                                .onTapGesture { ItemActions.copyToPasteboard(item) }
                        }
                    }.padding(12)
                }
            }
        }
    }
}

/// Settings wrapped for the dashboard (reuses the same controls, no back button).
private struct DashboardSettings: View {
    var body: some View {
        SettingsView(onBack: nil)
    }
}
