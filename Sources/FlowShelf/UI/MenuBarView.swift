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

    private var results: [ShelfItem] {
        store.visibleItems.filter { item in
            guard filter.matches(item) else { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return item.title.lowercased().contains(q)
                || item.preview.lowercased().contains(q)
                || (item.text?.lowercased().contains(q) ?? false)
                || (item.sourceApp?.lowercased().contains(q) ?? false)
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
            footerButton("rectangle.3.group", "Open Dashboard · ⌘⇧D") {
                DashboardWindowController.shared.show()
            }
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
