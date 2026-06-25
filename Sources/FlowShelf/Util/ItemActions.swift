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

    /// Float the image on top of everything as a draggable pin (Shottr-style).
    static func pin(_ item: ShelfItem) {
        guard let url = ShelfStore.shared.imageURL(for: item),
              let img = NSImage(contentsOf: url) else { return }
        PinController.shared.pin(img)
    }

    /// Stitch this image together with others the user picks, into one tall canvas.
    static func combine(_ item: ShelfItem) {
        guard let base = loadImage(item) else { return }
        let extra = pickImages(message: "Choose image(s) to stack below this one")
        guard !extra.isEmpty else { return }
        guard let out = ImageTools.stack([base] + extra, vertical: true, gap: 12, bg: .white) else { return }
        shelf(out, title: "Combined", prefix: "combined")
    }

    /// Build a 2-frame before/after GIF from this image plus one the user picks.
    static func beforeAfterGIF(_ item: ShelfItem) {
        guard let before = loadImage(item) else { return }
        guard let after = pickImages(message: "Choose the “after” image", multiple: false).first else { return }
        let frames = ImageTools.normalize([before, after])
        guard let data = ImageTools.makeGIF(frames: frames, seconds: 0.8) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "before-after.gif"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }

    // MARK: helpers for the multi-image tools

    private static func loadImage(_ item: ShelfItem) -> NSImage? {
        guard let url = ShelfStore.shared.imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func pickImages(message: String, multiple: Bool = true) -> [NSImage] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = message
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { NSImage(contentsOf: $0) }
    }

    private static func shelf(_ image: NSImage, title: String, prefix: String) {
        guard let (rel, thumb) = ShelfStore.shared.storeImage(image, prefix: prefix) else { return }
        ShelfStore.shared.add(ShelfItem(kind: .screenshot, title: title,
            preview: "\(title) \(Date().shortTime)", sourceApp: "Image Tools",
            imageRelPath: rel, thumbRelPath: thumb))
    }

    /// Decode a QR / barcode in the image; result is shelfed + copied.
    static func scanQR(_ item: ShelfItem) {
        guard let url = ShelfStore.shared.imageURL(for: item),
              let img = NSImage(contentsOf: url) else { return }
        ScreenshotService.shared.decodeQR(in: img) { payload in
            if payload == nil {
                let alert = NSAlert()
                alert.messageText = "No QR code found"
                alert.informativeText = "FlowShelf couldn’t find a QR or barcode in this image."
                alert.runModal()
            }
        }
    }

    // MARK: - On-device AI (runs only on explicit user action)

    private static func aiText(of item: ShelfItem) -> String? {
        let t = item.text ?? item.preview
        return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : t
    }

    static func aiSummarize(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        AIResultPresenter.shared.present(title: "Summary") { await AIService.summarize(text) }
    }

    static func aiCleanUp(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        AIResultPresenter.shared.present(title: "Cleaned text") { await AIService.cleanUp(text) }
    }

    static func aiTitle(_ item: ShelfItem) {
        guard let text = aiText(of: item) else { return }
        Task {
            guard let out = await AIService.title(for: text) else { return }
            ShelfStore.shared.updateTitle(item.id, out)
        }
    }

    /// Run a transform and show the result in the small AI window.
    static func aiTransform(_ item: ShelfItem, instruction: String, title: String) {
        guard let text = aiText(of: item) else { return }
        AIResultPresenter.shared.present(title: title) {
            await AIService.transform(text, instruction: instruction)
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

    /// General assistant — asks the user a question and answers using the shelf
    /// (and snippets) as context.
    static func aiAskGeneral() {
        guard let q = prompt(title: "Ask AI",
                             message: "Ask anything — I'll check your shelf for context first.",
                             default: "", placeholder: "e.g. What did I save about taxes?") else { return }
        var context = ShelfStore.shared.visibleItems.compactMap { item -> String? in
            let t = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        context += SnippetStore.shared.snippets.map { "\($0.title): \($0.content)" }
        AIResultPresenter.shared.present(title: "Ask AI") {
            await AIService.ask(question: q, shelf: context)
        }
    }

    static func aiSummarizeDay() {
        let texts = ShelfStore.shared.visibleItems.compactMap { item -> String? in
            let t = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard !texts.isEmpty else { return }
        AIResultPresenter.shared.present(title: "Today’s summary") {
            await AIService.summarizeDay(texts)
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
        alert.window.initialFirstResponder = field   // type immediately, no extra click
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
