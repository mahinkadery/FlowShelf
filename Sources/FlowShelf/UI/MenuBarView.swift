import SwiftUI

enum ShelfFilter: String, CaseIterable, Identifiable {
    case today, pinned, screenshots, files, links, text
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .pinned: return "Pinned"
        case .screenshots: return "Shots"
        case .files: return "Files"
        case .links: return "Links"
        case .text: return "Text"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "tray.full"
        case .pinned: return "pin"
        case .screenshots: return "camera.viewfinder"
        case .files: return "doc"
        case .links: return "link"
        case .text: return "text.alignleft"
        }
    }

    func matches(_ item: ShelfItem) -> Bool {
        switch self {
        case .today: return true
        case .pinned: return item.pinned
        case .screenshots: return item.kind == .screenshot || item.kind == .image
        case .files: return item.kind == .file
        case .links: return item.kind == .link
        case .text: return item.kind == .text || item.kind == .ocr
        }
    }
}

/// The content shown when you click the menu-bar icon. The heart of the app:
/// search + a single list of today's temporary items.
struct MenuBarView: View {
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var filter: ShelfFilter = .today
    @State private var showSettings = false
    @State private var aiResultIDs: [UUID]? = nil   // non-nil = showing AI search results
    @State private var aiSearching = false

    private var aiActive: Bool { aiResultIDs != nil }
    private var canSmartSearch: Bool {
        AIService.isSupported && settings.aiEnabled && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var results: [ShelfItem] {
        if let ids = aiResultIDs {
            let map = Dictionary(store.visibleItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return ids.compactMap { map[$0] }
        }
        let tokens = SearchQuery.tokens(query)
        return store.visibleItems.filter { filter.matches($0) && $0.matches(searchTokens: tokens) }
    }

    private func runAISearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        aiSearching = true
        let candidates = store.visibleItems.map {
            (id: $0.id.uuidString, text: "\($0.title) \($0.preview) \($0.text ?? "")")
        }
        Task {
            let ids = await AIService.smartSearch(query: q, candidates: candidates)
            await MainActor.run {
                aiResultIDs = ids.compactMap { UUID(uuidString: $0) }
                aiSearching = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(onBack: { showSettings = false })
            } else {
                header
                Divider()
                filterBar
                Divider()
                list
                Divider()
                footer
            }
        }
        .frame(width: 360, height: 460)
        .onDrop(of: [.fileURL, .image, .text], isTargeted: nil) { providers in
            DragDrop.ingest(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search today’s shelf…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { if canSmartSearch { runAISearch() } }
                .onChange(of: query) { _, _ in aiResultIDs = nil }   // back to normal search
            if aiSearching {
                ProgressView().controlSize(.small)
            } else if aiActive {
                Button { aiResultIDs = nil } label: {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain).help("Clear AI results")
            } else if canSmartSearch {
                Button { runAISearch() } label: {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Smart search with AI · ⏎")
            }
            if settings.privateMode {
                Label("Private", systemImage: "eye.slash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("Clipboard capture paused")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShelfFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Label(f.label, systemImage: f.symbol)
                            .font(.system(size: 11))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(filter == f
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(filter == f ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    @ViewBuilder private var list: some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(query.isEmpty ? "Nothing on the shelf yet" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Copy something, take a screenshot (⌘⇧7),\nor drop a file here.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { item in
                        ShelfItemRow(item: item)
                            .onTapGesture { ItemActions.copyToPasteboard(item) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            footerButton("camera.viewfinder", "Screenshot · ⌘⇧7") {
                ScreenshotService.shared.captureRegion(runOCR: false)
            }
            footerButton("text.viewfinder", "Screenshot + OCR · ⌘⇧O") {
                ScreenshotService.shared.captureRegion(runOCR: true)
            }
            footerButton(settings.privateMode ? "eye.slash" : "eye",
                         settings.privateMode ? "Resume clipboard" : "Private mode") {
                settings.privateMode.toggle()
            }
            Button { DashboardWindowController.shared.show() } label: {
                Label("App", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Open the full FlowShelf app · ⌘⇧D")
            Spacer()
            footerButton("trash", "Clear unpinned") {
                store.clearAll(includingPinned: false)
            }
            footerButton("gearshape", "Settings") { showSettings = true }
            footerButton("power", "Quit FlowShelf") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footerButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
