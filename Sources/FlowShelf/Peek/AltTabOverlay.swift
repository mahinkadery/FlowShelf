import SwiftUI
import AppKit

/// Backing state for the Option+Tab switcher overlay.
@MainActor
final class AltTabModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex = 0
    @Published var layout: AltTabLayout = .thumbnails
}

/// The centered switcher card shown while Option+Tab is held.
struct AltTabOverlayView: View {
    @ObservedObject var model: AltTabModel

    var body: some View {
        Group {
            if model.layout == .list { listLayout } else { thumbnailLayout }
        }
        .padding(16)
        .frame(maxWidth: model.layout == .list ? 460 : 980)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: Thumbnails (a balanced grid: 2×2, then 3×3, then 4×4 …)

    /// Square-ish grid that grows with the window count (2 cols up to 4 windows,
    /// 3 up to 9, 4 up to 16, capped at 5).
    private var columnCount: Int {
        let n = model.windows.count
        if n <= 1 { return 1 }
        return min(max(2, Int(ceil(Double(n).squareRoot()))), 5)
    }

    private var thumbnailLayout: some View {
        let columns = Array(repeating: GridItem(.fixed(178), spacing: 14), count: columnCount)
        return VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(model.windows.enumerated()), id: \.element.id) { i, w in
                    thumbCard(w, selected: i == model.selectedIndex)
                }
            }
            if let sel = currentTitle {
                Text(sel).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func thumbCard(_ w: WindowInfo, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let t = w.thumbnail {
                    Image(nsImage: t).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let icon = appIcon(w.pid) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48).opacity(0.7)
                }
            }
            .frame(width: 176, height: 116)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 3 : 1))
            HStack(spacing: 4) {
                if let icon = appIcon(w.pid) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(w.title).font(.system(size: 10)).lineLimit(1)
            }
            .frame(width: 176)
        }
        .scaleEffect(selected ? 1.0 : 0.97)
    }

    // MARK: List (compact rows)

    private var listLayout: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.windows.enumerated()), id: \.element.id) { i, w in
                HStack(spacing: 10) {
                    if let icon = appIcon(w.pid) {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(w.title).font(.system(size: 13)).lineLimit(1)
                        Text(w.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(i == model.selectedIndex ? Color.accentColor.opacity(0.22) : Color.clear))
            }
        }
    }

    private var currentTitle: String? {
        guard model.windows.indices.contains(model.selectedIndex) else { return nil }
        return model.windows[model.selectedIndex].title
    }

    private func appIcon(_ pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
