import AppKit
@preconcurrency import Vision

/// Region screenshots + local OCR.
///
/// We shell out to the system `screencapture` for the region selection UI — it's
/// the same crosshair users already know, handles multi-display, and the Screen
/// Recording permission prompt is managed by the OS. OCR runs locally via Vision.
@MainActor
final class ScreenshotService {
    static let shared = ScreenshotService()
    private let store = ShelfStore.shared
    private init() {}

    /// Capture a user-selected region and add it to the Shelf.
    /// - Parameter ocr: also run OCR and add the recognized text as a separate item.
    func captureRegion(runOCR ocr: Bool) {
        runCapture(extraArgs: ["-i"], runOCR: ocr)
    }

    /// Capture a single window cleanly. `-w` is window-pick mode; combined with the
    /// shared `-o` it drops the OS window shadow so backdrops look right.
    func captureWindow(runOCR ocr: Bool = false) {
        runCapture(extraArgs: ["-w"], runOCR: ocr)
    }

    private func runCapture(extraArgs: [String], runOCR ocr: Bool) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowshelf-\(UUID().uuidString).png")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -o no window shadow, -x no sound (plus caller's interactive/delay args).
        proc.arguments = extraArgs + ["-o", "-x", tmp.path]

        proc.terminationHandler = { _ in
            Task { @MainActor in
                self.finishCapture(at: tmp, runOCR: ocr)
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("FlowShelf: screencapture failed: \(error)")
        }
    }

    private func finishCapture(at url: URL, runOCR ocr: Bool) {
        // User pressed Esc → no file written.
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else { return }
        defer { try? FileManager.default.removeItem(at: url) }

        // If the user wants to mark up shots, hand off to the annotation editor
        // (it adds the result to the Shelf itself). Otherwise shelf it directly.
        if AppSettings.shared.annotateAfterScreenshot {
            AnnotationEditorController.shared.open(image: image)
        } else if let (rel, thumb) = store.storeImage(image, prefix: "shot") {
            store.add(ShelfItem(
                kind: .screenshot,
                title: "Screenshot",
                preview: "Captured \(Date().shortTime)",
                sourceApp: "FlowShelf",
                imageRelPath: rel,
                thumbRelPath: thumb
            ))
        }

        if ocr { recognizeText(in: image) }
    }

    /// Run OCR on an arbitrary NSImage and shelf the result. Reusable by the
    /// "OCR this" action on existing image items.
    func recognizeText(in image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let request = VNRecognizeTextRequest { request, _ in
            let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            Task { @MainActor in
                self.store.add(ShelfItem(
                    kind: .ocr,
                    title: trimmed.firstLine(),
                    preview: trimmed.firstLine(max: 140),
                    text: trimmed,
                    sourceApp: "OCR"
                ))
                // OCR text is immediately useful — drop it on the clipboard too.
                let pb = NSPasteboard.general
                AppSettings.shared.ignoreNextCopy = true
                pb.clearContents()
                pb.setString(trimmed, forType: .string)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        // Vision work off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    /// Decode any QR / barcode in an image. Shelfs the payload (and opens it on the
    /// clipboard) when found; calls `onResult` with the decoded string or nil.
    func decodeQR(in image: NSImage, onResult: ((String?) -> Void)? = nil) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            onResult?(nil); return
        }

        let request = VNDetectBarcodesRequest { request, _ in
            let payload = (request.results as? [VNBarcodeObservation] ?? [])
                .compactMap { $0.payloadStringValue }
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Task { @MainActor in
                if let payload, !payload.isEmpty {
                    self.store.add(ShelfItem(
                        kind: payload.looksLikeURL ? .link : .text,
                        title: payload.firstLine(),
                        preview: payload.firstLine(max: 140),
                        text: payload,
                        sourceApp: "QR"
                    ))
                    let pb = NSPasteboard.general
                    AppSettings.shared.ignoreNextCopy = true
                    pb.clearContents()
                    pb.setString(payload, forType: .string)
                }
                onResult?(payload)
            }
        }
        request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417, .code128, .ean13]

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
