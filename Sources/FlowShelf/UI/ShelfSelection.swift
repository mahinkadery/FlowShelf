import SwiftUI
import AppKit

enum ShelfSelectionLayout {
    case row, tile
}

private struct ShelfSelectionOverlay: ViewModifier {
    let item: ShelfItem
    let layout: ShelfSelectionLayout
    @Binding var selection: Set<UUID>

    private var isSelected: Bool { selection.contains(item.id) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: layout == .row ? .trailing : .topTrailing) {
                Button {
                    if isSelected { selection.remove(item.id) }
                    else { selection.insert(item.id) }
                } label: {
                    ZStack {
                        if layout == .tile {
                            Circle().fill(.black.opacity(0.45))
                        }
                        Circle().strokeBorder(layout == .tile ? Color.white.opacity(0.85) : Color.primary.opacity(0.38), lineWidth: 1.25)
                        if isSelected {
                            Circle().fill(Color.accentColor)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: layout == .row ? 16 : 18, height: layout == .row ? 16 : 18)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(item.title.isEmpty ? item.kind.label : item.title)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .help(isSelected ? "Deselect item" : "Select item without copying")
                .padding(.trailing, layout == .row ? 6 : 1)
                .padding(.top, layout == .row ? 0 : 1)
            }
    }
}

extension View {
    func shelfSelection(item: ShelfItem, selection: Binding<Set<UUID>>, layout: ShelfSelectionLayout = .row) -> some View {
        modifier(ShelfSelectionOverlay(item: item, layout: layout, selection: selection))
    }
}

struct ShelfSelectionActions: View {
    let items: [ShelfItem]
    @Binding var selection: Set<UUID>
    @State private var status = ""

    private var selectedItems: [ShelfItem] { items.filter { selection.contains($0.id) } }
    private var fileCount: Int {
        selectedItems.filter { [.file, .image, .screenshot].contains($0.kind) }.count
    }
    private var isMixed: Bool { fileCount > 0 && fileCount < selectedItems.count }
    private var copyLabel: String { fileCount > 0 ? "Copy files" : "Copy as text" }

    private func prepare() throws -> [ShelfBatchTransfer.Entry] {
        let visibleIDs = Set(ShelfStore.shared.visibleItems.map(\.id))
        let currentItems = selectedItems.filter { visibleIDs.contains($0.id) }
        guard currentItems.count == selection.count else {
            throw ShelfBatchTransfer.TransferError.unavailable("A selected item")
        }
        return try ShelfBatchTransfer.prepare(currentItems, imageURL: ShelfStore.shared.imageURL(for:))
    }

    private func copy() {
        do {
            let writers = try ShelfBatchTransfer.copyWriters(prepare())
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects(writers) else {
                status = "Could not write the clipboard. Please try again."
                return
            }
            Haptics.copy()
            status = fileCount > 0 ? "Copied \(writers.count) files."
                : "Copied \(selectedItems.count) items as plain text, in shelf order."
        } catch {
            status = error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("\(selectedItems.count)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("\(selectedItems.count) selected")
                Button { selection.removeAll() } label: {
                    Image(systemName: "xmark").frame(width: 22, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear selection")
                .help("Clear selection")
                Spacer(minLength: 0)
                Button("Copy") { copy() }
                    .disabled(selectedItems.isEmpty || isMixed)
                    .help("\(copyLabel). Text is joined with blank lines in shelf order. Images are copied as files.")
                BatchDragHandle(count: selectedItems.count, prepare: prepare) { status = $0 }
                    .frame(width: 116, height: 28)
            }
            if !status.isEmpty || isMixed {
                Text(status.isEmpty ? "Mixed types: drag to an app that accepts them." : status)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .onChange(of: selection) { _, _ in status = "" }
    }
}
