import AppKit

/// Shared actions a Shelf item supports (copy, reveal, open, OCR).
@MainActor
enum ItemActions {
    static func copyToPasteboard(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        AppSettings.shared.ignoreNextCopy = true   // don't re-shelf our own copy
        pb.clearContents()

        switch item.kind {
        case .image, .screenshot:
            if let url = ShelfStore.shared.imageURL(for: item),
               let img = NSImage(contentsOf: url) {
                pb.writeObjects([img])
            }
        case .file:
            if let path = item.filePath {
                pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        default:
            pb.setString(item.text ?? item.preview, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        if item.kind == .file, let path = item.filePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let url = ShelfStore.shared.imageURL(for: item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .link:
            if let text = item.text, let url = URL(string: text) { NSWorkspace.shared.open(url) }
        case .file:
            if let path = item.filePath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case .image, .screenshot:
            if let url = ShelfStore.shared.imageURL(for: item) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    static func runOCR(_ item: ShelfItem) {
        guard let url = ShelfStore.shared.imageURL(for: item),
              let img = NSImage(contentsOf: url) else { return }
        ScreenshotService.shared.recognizeText(in: img)
    }
}
