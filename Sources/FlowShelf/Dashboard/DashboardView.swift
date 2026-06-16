import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case shelf, peek, clean, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shelf: return "Shelf"
        case .peek: return "Peek"
        case .clean: return "Clean"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .shelf: return "tray.full"
        case .peek: return "rectangle.on.rectangle"
        case .clean: return "trash"
        case .settings: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .shelf: return "Today’s items"
        case .peek: return "Window previews"
        case .clean: return "App cleaner"
        case .settings: return "Preferences"
        }
    }
}

/// The unified dashboard. One window, the Shelf at its heart, with Peek and
/// Clean living alongside it.
struct DashboardView: View {
    @State private var section: DashboardSection = .shelf

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $section) { item in
                NavigationLink(value: item) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).font(.system(size: 13))
                            Text(item.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 7) {
                    Image(systemName: "tray.full.fill").foregroundStyle(.tint)
                    Text("FlowShelf").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        } detail: {
            Group {
                switch section {
                case .shelf:    ShelfBrowser()
                case .peek:     PeekView()
                case .clean:    CleanView()
                case .settings: DashboardSettings()
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity,
                   alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

/// A roomier Shelf for the dashboard — same items, filter chips, search.
private struct ShelfBrowser: View {
    @ObservedObject private var store = ShelfStore.shared
    @State private var query = ""
    @State private var filter: ShelfFilter = .today

    private var results: [ShelfItem] {
        store.visibleItems.filter { item in
            guard filter.matches(item) else { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return item.title.lowercased().contains(q)
                || item.preview.lowercased().contains(q)
                || (item.text?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shelf").font(.system(size: 15, weight: .semibold))
                Text("\(store.visibleItems.count)").foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Search…", text: $query).textFieldStyle(.plain).frame(width: 180)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            .padding(14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ShelfFilter.allCases) { f in
                        Button { filter = f } label: {
                            Label(f.label, systemImage: f.symbol).font(.system(size: 11))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(filter == f
                                    ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                                .foregroundStyle(filter == f ? Color.accentColor : .primary)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider()

            if results.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "Nothing on the shelf yet" : "No matches")
                        .foregroundStyle(.secondary).font(.system(size: 12))
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { item in
                            ShelfItemRow(item: item)
                                .onTapGesture(count: 2) { ItemActions.open(item) }
                                .onTapGesture { ItemActions.copyToPasteboard(item) }
                        }
                    }.padding(8)
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
