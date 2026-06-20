import SwiftUI

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var targeted = false
    /// Size of the physical notch (the collapsed card). Updated by the controller.
    @Published var collapsedSize = CGSize(width: 200, height: 32)
    /// Size of the open panel — wide and slim, like a Dynamic Island bar.
    let expandedSize = CGSize(width: 560, height: 124)
}

/// The signature Dynamic-Island silhouette: a flat top edge flush with the screen
/// edge, **concave** (inverted) corners curving down into the sides, then rounded
/// bottom corners — so the card looks like it grows out of the notch.
struct NotchShape: Shape {
    var topRadius: CGFloat = 9
    var bottomRadius: CGFloat = 20

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius, rect.width / 2)
        let br = min(bottomRadius, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The notch card. The window stays a fixed size; this card morphs between the
/// collapsed (notch-sized) and expanded shapes with a spring — that's the smooth
/// Dynamic-Island feel.
struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var store = ShelfStore.shared

    private var recent: [ShelfItem] { Array(store.visibleItems.prefix(7)) }
    private var size: CGSize { model.expanded ? model.expandedSize : model.collapsedSize }
    private var shape: NotchShape {
        NotchShape(topRadius: model.expanded ? 12 : 6, bottomRadius: model.expanded ? 28 : 10)
    }

    var body: some View {
        card
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.80), value: model.expanded)
    }

    private var card: some View {
        ZStack(alignment: .top) {
            Color.black

            // Expanded content lives at its full size and is revealed as the card
            // grows (clipped to the shape), so it never squishes mid-animation.
            expandedContent
                .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
                .opacity(model.expanded ? 1 : 0)

            if !model.expanded {
                VStack {
                    Spacer()
                    Capsule().fill(.white.opacity(model.targeted ? 0.6 : 0.14))
                        .frame(width: 24, height: 3).padding(.bottom, 2)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(model.targeted ? Color.accentColor : Color.white.opacity(0.10),
                              lineWidth: model.targeted ? 2 : 1))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(model.expanded ? 0.45 : 0), radius: 16, y: 6)
        .contentShape(shape)
        // Open/close is driven by the controller's swipe-aware mouse monitor.
        // Dragging onto the notch still opens it so it can accept the drop.
        .onDrop(of: [.fileURL, .image, .text], isTargeted: Binding(
            get: { model.targeted },
            set: { t in
                model.targeted = t
                if t { model.expanded = true }
                else { NotchController.shared.scheduleCollapseAll() }
            }
        )) { providers in
            DragDrop.ingest(providers)
        }
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Reserve the camera-notch strip at the very top so nothing hides
            // behind it, then vertically centre the row in the space below.
            Color.clear.frame(height: model.collapsedSize.height)

            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Shelf").font(.system(size: 11, weight: .semibold))
                        Text("\(store.visibleItems.count) item\(store.visibleItems.count == 1 ? "" : "s")")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .fixedSize()

                Divider().frame(height: 38).overlay(Color.white.opacity(0.12))

                Group {
                    if recent.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 13))
                            Text("Drop files, images, or text").font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(model.targeted ? 0.85 : 0.5))
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recent) { NotchTile(item: $0) }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 38).overlay(Color.white.opacity(0.12))

                Button { DashboardWindowController.shared.show() } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 13))
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                .help("Open the full shelf")
                .fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

}

/// A compact, type-aware tile in the expanded notch: click to copy, drag out.
/// Each kind looks distinct (image thumbnail, link host, file name, text snippet)
/// so a row of them reads as content rather than a row of identical glyphs.
private struct NotchTile: View {
    let item: ShelfItem
    @ObservedObject private var store = ShelfStore.shared
    private let side: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint)
            content
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.10)))
        .contentShape(Rectangle())
        .onTapGesture { ItemActions.copyToPasteboard(item) }
        .onDrag { DragDrop.provider(for: item) }
        .help(item.preview)
    }

    @ViewBuilder private var content: some View {
        if item.hasImage, let thumb = store.thumbnail(for: item) {
            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if item.kind == .file {
            label(icon: "doc.fill", caption: item.title)
        } else if item.kind == .link {
            label(icon: "link", caption: URL(string: item.text ?? "")?.host ?? item.title)
        } else {
            // text / OCR: show a small snippet so each tile is distinguishable.
            Text(item.preview)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
        }
    }

    private func label(icon: String, caption: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
            Text(caption).font(.system(size: 7)).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 4)
    }

    private var tint: Color {
        switch item.kind {
        case .link: return Color.blue.opacity(0.20)
        case .file: return Color.orange.opacity(0.16)
        default:    return Color.white.opacity(0.07)
        }
    }
}
