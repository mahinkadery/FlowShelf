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

    static func annotate(_ item: ShelfItem) {
        guard let url = ShelfStore.shared.imageURL(for: item),
              let img = NSImage(contentsOf: url) else { return }
        AnnotationEditorController.shared.open(image: img)
    }

    // MARK: - On-device AI (runs only on explicit user action)

    private static func aiText(of item: ShelfItem) -> String? {
        let t = item.text ?? item.preview
        return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : t
    }

    static func aiSummarize(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        Task {
            guard let out = await AIService.summarize(text) else { return }
            ShelfStore.shared.add(ShelfItem(kind: .text, title: "Summary",
                preview: out.firstLine(max: 140), text: out, sourceApp: "AI"))
        }
    }

    static func aiCleanUp(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        Task {
            guard let out = await AIService.cleanUp(text) else { return }
            ShelfStore.shared.add(ShelfItem(kind: .text, title: "Cleaned text",
                preview: out.firstLine(max: 140), text: out, sourceApp: "AI"))
        }
    }

    static func aiTitle(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        Task {
            guard let out = await AIService.title(for: text) else { return }
            ShelfStore.shared.updateTitle(item.id, out)
        }
    }

    /// Run a transform and drop the result onto the shelf as a new text item.
    static func aiTransform(_ item: ShelfItem, instruction: String, title: String) {
        guard let text = aiText(of: item) else { return }
        Task {
            guard let out = await AIService.transform(text, instruction: instruction) else { return }
            ShelfStore.shared.add(ShelfItem(kind: .text, title: title,
                preview: out.firstLine(max: 140), text: out, sourceApp: "AI"))
        }
    }

    static func aiTranslate(_ item: ShelfItem) {
        guard aiText(of: item) != nil else { return }
        guard let lang = prompt(title: "Translate", message: "Translate to which language?", default: "English") else { return }
        aiTransform(item,
            instruction: "Translate the following into \(lang). Reply with only the translation.",
            title: "Translation (\(lang))")
    }

    static func aiAsk(_ item: ShelfItem) {
        guard aiText(of: item) != nil else { return }
        guard let instr = prompt(title: "Ask AI", message: "What should AI do with this item?",
                                 default: "", placeholder: "e.g. Turn this into a tweet") else { return }
        aiTransform(item, instruction: "\(instr). Reply with only the result.",
                    title: "AI: \(String(instr.prefix(28)))")
    }

    static func aiSummarizeDay() {
        let texts = ShelfStore.shared.visibleItems.compactMap { item -> String? in
            let t = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard !texts.isEmpty else { return }
        Task {
            guard let out = await AIService.summarizeDay(texts) else { return }
            ShelfStore.shared.add(ShelfItem(kind: .text, title: "Today’s summary",
                preview: out.firstLine(max: 140), text: out, sourceApp: "AI"))
        }
    }

    /// Small modal text prompt (used by the custom AI actions).
    private static func prompt(title: String, message: String,
                               default def: String, placeholder: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = def
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
