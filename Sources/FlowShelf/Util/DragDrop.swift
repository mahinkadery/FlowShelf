import AppKit
import UniformTypeIdentifiers

/// Bridges AppKit/SwiftUI drag-and-drop into and out of the Shelf.
enum DragDrop {

    /// Ingest dropped item providers into the Shelf. Returns true if anything handled.
    @MainActor
    static func ingest(_ providers: [NSItemProvider]) -> Bool {
        let store = ShelfStore.shared
        var handled = false

        for provider in providers {
            // File URL — store as reference.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let bookmark = try? url.bookmarkData(options: .minimalBookmark)
                    Task { @MainActor in
                        store.add(ShelfItem(
                            kind: .file,
                            title: url.lastPathComponent,
                            preview: url.deletingLastPathComponent().path,
                            sourceApp: "Drop",
                            fileBookmark: bookmark,
                            filePath: url.path
                        ))
                    }
                }
                continue
            }

            // Image.
            if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    Task { @MainActor in
                        if let (rel, thumb) = store.storeImage(img, prefix: "drop") {
                            store.add(ShelfItem(kind: .image, title: "Image",
                                                preview: "Dropped image", sourceApp: "Drop",
                                                imageRelPath: rel, thumbRelPath: thumb))
                        }
                    }
                }
                continue
            }

            // Plain text / link.
            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let s = obj as? String,
                          !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { @MainActor in
                        let isLink = s.looksLikeURL
                        store.add(ShelfItem(
                            kind: isLink ? .link : .text,
                            title: isLink ? (URL(string: s)?.host ?? "Link") : s.firstLine(),
                            preview: s.firstLine(max: 140),
                            text: s, sourceApp: "Drop"))
                    }
                }
            }
        }
        return handled
    }

    /// Build an NSItemProvider for dragging an item OUT of the Shelf.
    @MainActor
    static func provider(for item: ShelfItem) -> NSItemProvider {
        let store = ShelfStore.shared

        // File: drag the real file (resolve bookmark first, fall back to path).
        if item.kind == .file {
            if let bookmark = item.fileBookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }
            }
            if let path = item.filePath {
                return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
            }
        }

        // Image/screenshot: drag the stored PNG file so it drops as an image file.
        if let url = store.imageURL(for: item) {
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }

        // Text/link/OCR: drag the text.
        let provider = NSItemProvider()
        let payload = item.text ?? item.preview
        provider.registerObject(payload as NSString, visibility: .all)
        return provider
    }
}
