import SwiftUI
import AppKit

/// The floating drop-shelf. A small always-on-top glass card you can drag files,
/// images, links, screenshots, or text into while moving between apps, then drag
/// (or copy) them back out at the destination.
struct FloatingShelfView: View {
    @ObservedObject private var store = ShelfStore.shared
    var onClose: () -> Void
    @State private var targeted = false
    @State private var filter: ShelfFilter = .today

    private var items: [ShelfItem] { store.visibleItems.filter { filter.matches($0) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                FlowShelfGlyph(size: 13, color: .secondary)
                Text("Shelf")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(store.visibleItems.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WindowMoveHandle())   // drag the panel by its header only

            // Filter chips (Today · Pinned · Shots · Files · Links · Text).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ShelfFilter.allCases) { f in
                        Button { filter = f } label: {
                            Label(f.label, systemImage: f.symbol).font(.system(size: 10))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(filter == f
                                    ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07)))
                                .foregroundStyle(filter == f ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 6)
            }

            Divider().opacity(0.5)

            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Drop files, images, links,\nor text here")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in
                            ShelfTile(item: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 300, height: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: targeted ? 2 : 1)
        )
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $targeted) { providers in
            DragDrop.ingest(providers)
        }
    }
}

/// A compact, type-aware tile. Click to copy, drag to move out, hover for actions.
private struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject private var store = ShelfStore.shared
    @State private var hovering = false
    @State private var copied = false

    private let tileW: CGFloat = 80
    private let tileH: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                content

                if item.pinned {
                    VStack { HStack { Spacer()
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange)
                            .padding(4)
                    }; Spacer() }
                }

                // Hover action bar (copy · pin · delete).
                if hovering && !copied {
                    VStack { Spacer()
                        HStack(spacing: 5) {
                            tileButton("doc.on.doc", "Copy") { copy() }
                            tileButton(item.pinned ? "pin.slash" : "pin", item.pinned ? "Unpin" : "Pin") {
                                store.togglePin(item.id)
                            }
                            tileButton("xmark", "Remove") { store.remove(item.id) }
                        }
                        .padding(4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 3)
                    }
                }

                // Brief "copied" confirmation.
                if copied {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(.green))
                }
            }
            .frame(width: tileW, height: tileH)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))

            Text(titleText)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: tileW)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { copy() }                    // click to copy
        .onDrag { DragDrop.provider(for: item) }    // drag to move out
        .contextMenu { menu }
        .help("\(item.preview) · \(item.expiryLabel)")
    }

    // Type-aware visual.
    @ViewBuilder private var content: some View {
        if item.hasImage, let thumb = store.thumbnail(for: item) {
            Image(nsImage: thumb)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: tileW, height: tileH)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if item.kind == .file, let icon = fileIcon {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
        } else if item.kind == .link {
            Image(systemName: "link").font(.system(size: 20)).foregroundStyle(.blue)
        } else {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 19)).foregroundStyle(.secondary)
        }
    }

    private var fileIcon: NSImage? {
        guard let path = item.filePath else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private var titleText: String {
        switch item.kind {
        case .link: return URL(string: item.text ?? "")?.host ?? item.title
        case .file: return item.title
        default:    return item.title.isEmpty ? item.kind.label : item.title
        }
    }

    private func copy() {
        ItemActions.copyToPasteboard(item)
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Copy") { copy() }
        if item.kind == .link || item.kind == .file || item.hasImage {
            Button("Open") { ItemActions.open(item) }
        }
        if item.kind == .file || item.hasImage {
            Button("Reveal in Finder") { ItemActions.reveal(item) }
        }
        if item.hasImage { Button("Run OCR") { ItemActions.runOCR(item) } }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item.id) }
        Button("Remove", role: .destructive) { store.remove(item.id) }
    }

    private func tileButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain).foregroundStyle(.primary).help(help)
    }
}

/// A transparent AppKit view that lets you move the window by dragging it.
/// Placed behind the header so tiles keep their own drag-out behavior.
private struct WindowMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MoveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class MoveView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Owns the floating NSPanel and toggles it on/off.
@MainActor
final class FloatingShelfController {
    static let shared = FloatingShelfController()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { makePanel() }
        positionAtCursor()
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() {
        let host = NSHostingView(rootView: FloatingShelfView(onClose: { [weak self] in self?.hide() }))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        // IMPORTANT: must be false, otherwise dragging a tile out of the shelf
        // moves the whole window instead. The header acts as the move handle.
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        panel = p
    }

    /// Open the shelf centered just under the pointer, clamped to its screen.
    private func positionAtCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation                 // global, bottom-left
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)

        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height + 28                // pointer near the top of the card
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
