import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Model

enum AnnoTool: String, CaseIterable, Identifiable {
    case arrow, box, highlight, step, blur, spotlight, text, crop, ruler, magnifier
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.left"
        case .box: return "rectangle"
        case .highlight: return "highlighter"
        case .step: return "1.circle.fill"
        case .blur: return "drop.degreesign"
        case .spotlight: return "rays"
        case .text: return "textformat"
        case .crop: return "crop"
        case .ruler: return "ruler"
        case .magnifier: return "magnifyingglass"
        }
    }
    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .highlight: return "Highlight"
        case .step: return "Step"
        case .blur: return "Blur"
        case .spotlight: return "Spotlight"
        case .text: return "Text"
        case .crop: return "Crop"
        case .ruler: return "Ruler"
        case .magnifier: return "Magnify"
        }
    }
}

/// Beautify backdrop — wraps the shot in a padded gradient with rounded corners
/// and a soft shadow (great for sharing). `.none` exports the bare image.
enum Backdrop: String, CaseIterable, Identifiable {
    case none, sunset, ocean, mint, graphite, paper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .mint: return "Mint"
        case .graphite: return "Graphite"
        case .paper: return "Paper"
        }
    }
    var colors: [Color]? {
        switch self {
        case .none: return nil
        case .sunset: return [Color(red: 0.98, green: 0.45, blue: 0.36), Color(red: 0.96, green: 0.27, blue: 0.51)]
        case .ocean: return [Color(red: 0.30, green: 0.47, blue: 0.95), Color(red: 0.36, green: 0.78, blue: 0.92)]
        case .mint: return [Color(red: 0.42, green: 0.86, blue: 0.66), Color(red: 0.24, green: 0.62, blue: 0.62)]
        case .graphite: return [Color(red: 0.20, green: 0.22, blue: 0.27), Color(red: 0.10, green: 0.11, blue: 0.14)]
        case .paper: return [Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.88, green: 0.87, blue: 0.84)]
        }
    }
    var gradient: LinearGradient? {
        colors.map { LinearGradient(colors: $0, startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
}

struct Anno: Identifiable {
    let id = UUID()
    var tool: AnnoTool
    var start: CGPoint
    var end: CGPoint
    var color: Color
    var lineWidth: CGFloat
    var text: String = ""
    /// Sub-style index, meaning depends on `tool` (e.g. arrow: 0=arrow,1=line,2=double).
    var variant: Int = 0
    /// Freehand path samples (used by the highlighter marker).
    var points: [CGPoint] = []

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

// MARK: - Window controller

@MainActor
final class AnnotationEditorController {
    static let shared = AnnotationEditorController()
    private var window: NSWindow?

    func open(image: NSImage) {
        window?.close()
        let host = NSHostingController(rootView: AnnotationEditorView(image: image) { [weak self] in
            self?.close()
        })
        let win = NSWindow(contentViewController: host)
        win.title = "Annotate Screenshot"
        win.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        win.isReleasedWhenClosed = false
        window = win
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.center()
    }

    private func close() {
        window?.close()
        window = nil
        if DashboardWindowController.shared.isVisible == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Editor view

struct AnnotationEditorView: View {
    var onClose: () -> Void

    @State private var image: NSImage
    @State private var displaySize: CGSize

    @State private var tool: AnnoTool = .arrow
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var annos: [Anno] = []
    @State private var current: Anno?
    @State private var editingTextID: UUID?

    // Per-tool sub-option memory + undo/redo.
    @State private var variants: [AnnoTool: Int] = [.text: 1]   // default text size = Medium
    @State private var redoStack: [Anno] = []

    // Heavy derived copies — built lazily on first use (a tall screenshot × N
    // eager copies was a multi-GB memory hit), and cleared on crop.
    @State private var pixelated: NSImage?
    @State private var blurred: NSImage?

    private var curVar: Int { variants[tool] ?? 0 }

    // Beautify backdrop.
    @State private var backdrop: Backdrop = .none

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _image = State(initialValue: image)
        _displaySize = State(initialValue: Self.fit(image.size))
    }

    /// Build the pixelate/blur copies the first time a redaction is needed.
    private func ensureRedaction() {
        if pixelated == nil { pixelated = AnnotationRender.pixelate(image) }
        if blurred == nil { blurred = AnnotationRender.gaussianBlur(image) }
    }

    private static func fit(_ s: CGSize) -> CGSize {
        let maxW: CGFloat = 1000, maxH: CGFloat = 680
        let scale = min(1, min(maxW / max(s.width, 1), maxH / max(s.height, 1)))
        return CGSize(width: max(s.width * scale, 200), height: max(s.height * scale, 150))
    }

    private var stepAnnos: [Anno] { annos.filter { $0.tool == .step } }

    /// Step badge label: "1,2,3…" (variant 0) or "A,B,C…" (variant 1).
    private static func stepLabel(_ index: Int, variant: Int) -> String {
        if variant == 1 { return String(UnicodeScalar(UInt8(65 + (index % 26)))) }
        return "\(index + 1)"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            toolOptions
            Divider()
            ScrollView([.horizontal, .vertical]) {
                styled(canvasContent(interactive: true)
                    .frame(width: displaySize.width, height: displaySize.height))
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
            Divider()
            actionBar
        }
        .frame(minWidth: max(displaySize.width + 60, 820), minHeight: displaySize.height + 130)
        .onChange(of: tool) { _, t in
            if t == .blur { ensureRedaction() }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(AnnoTool.allCases) { t in
                Button { tool = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.system(size: 14))
                        Text(t.label).font(.system(size: 9))
                    }
                    .frame(width: 46, height: 38)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(tool == t ? Color.accentColor.opacity(0.2) : Color.clear))
                    .foregroundStyle(tool == t ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .help(t == .crop ? "Drag a region to crop" : t.label)
            }
            Divider().frame(height: 30)
            ColorPicker("", selection: $color).labelsHidden().frame(width: 38)
            VStack(spacing: 1) {
                Text("Size").font(.system(size: 9)).foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 2...14).frame(width: 80)
            }
            Spacer()
            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }.disabled(annos.isEmpty).help("Undo (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)
            Button { redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }.disabled(redoStack.isEmpty).help("Redo (⇧⌘Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button(role: .destructive) { annos.removeAll(); redoStack.removeAll() } label: {
                Image(systemName: "trash")
            }.disabled(annos.isEmpty).help("Clear all")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func undo() { if let last = annos.popLast() { redoStack.append(last) } }
    private func redo() { if let a = redoStack.popLast() { annos.append(a) } }

    // MARK: Tool options (contextual sub-tools)

    /// Sub-option labels for the current tool — every tool exposes a row.
    private var toolOptionLabels: [String] {
        switch tool {
        case .arrow:     return ["Arrow", "Line", "Double"]
        case .box:       return ["Outline", "Filled", "Rounded", "Ellipse"]
        case .highlight: return ["Marker", "Block"]
        case .step:      return ["1, 2, 3", "A, B, C"]
        case .blur:      return ["Pixelate", "Blur", "Solid"]
        case .spotlight: return ["Rectangle", "Ellipse"]
        case .text:      return ["Small", "Medium", "Large", "XL"]
        case .crop:      return ["Free", "1:1", "16:9", "4:3"]
        case .ruler:     return ["Length", "Width × Height"]
        case .magnifier: return ["2×", "2.5×", "3×"]
        }
    }

    /// Magnifier callout zoom factor by sub-option.
    private static func zoomFactor(_ variant: Int) -> CGFloat {
        switch variant { case 1: return 2.5; case 2: return 3; default: return 2 }
    }

    private var toolOptions: some View {
        HStack(spacing: 6) {
            Text(tool.label).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            ForEach(Array(toolOptionLabels.enumerated()), id: \.offset) { i, label in
                Button { variants[tool] = i } label: {
                    Text(label).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(curVar == i
                            ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
                        .foregroundStyle(curVar == i ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Backdrop wrapper

    /// Wrap the canvas in the chosen beautify backdrop (no-op for `.none`). Applied
    /// identically on screen and at export so what you see is what you get.
    @ViewBuilder
    private func styled(_ inner: some View) -> some View {
        if let gradient = backdrop.gradient {
            let pad = max(min(displaySize.width, displaySize.height) * 0.08, 30)
            inner
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                .padding(pad)
                .background(gradient)
        } else {
            inner
        }
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvasContent(interactive: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable()
                .frame(width: displaySize.width, height: displaySize.height)

            // Spotlight: dim everything except the highlighted region(s).
            let holes = spotlightHoles(interactive: interactive)
            if !holes.isEmpty {
                SpotlightMask(holes: holes, canvas: displaySize)
            }

            // Committed redaction regions (pixelate / blur / solid).
            ForEach(annos.filter { $0.tool == .blur }) { a in
                RedactView(anno: a, pixelated: pixelated ?? image, blurred: blurred ?? image, canvas: displaySize)
            }
            // Live redaction preview while dragging + dashed box under cursor.
            if interactive, let c = current, c.tool == .blur {
                RedactView(anno: c, pixelated: pixelated ?? image, blurred: blurred ?? image, canvas: displaySize)
                Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .frame(width: c.rect.width, height: c.rect.height)
                    .position(x: c.rect.midX, y: c.rect.midY)
            }

            // Shapes (arrow/box) + highlighter marker strokes.
            ForEach(annos.filter { $0.tool == .arrow || $0.tool == .box || $0.tool == .highlight }) { a in
                AnnoShapeView(anno: a)
            }
            if let current, current.tool == .arrow || current.tool == .box || current.tool == .highlight {
                AnnoShapeView(anno: current)
            }

            // Ruler measurements (line + live pixel length; baked into exports).
            ForEach(annos.filter { $0.tool == .ruler }) { a in
                RulerView(anno: a, scale: pxScale)
            }
            if let c = current, c.tool == .ruler {
                RulerView(anno: c, scale: pxScale)
            }

            // Step badges (numbered or lettered in placement order).
            ForEach(Array(stepAnnos.enumerated()), id: \.element.id) { i, a in
                StepBadge(label: Self.stepLabel(i, variant: a.variant), color: a.color,
                          diameter: max(a.lineWidth * 5, 24))
                    .position(x: a.start.x, y: a.start.y)
            }

            // Crop selection (interactive only — not exported).
            if interactive, let c = current, c.tool == .crop {
                Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .frame(width: c.rect.width, height: c.rect.height)
                    .position(x: c.rect.midX, y: c.rect.midY)
            }

            // Magnifier callouts: a selected region shown enlarged over the spot
            // (baked into exports). Light on memory — only the small region is scaled.
            ForEach(annos.filter { $0.tool == .magnifier }) { a in
                if let crop = cropImage(a.rect) {
                    ZoomCallout(crop: crop, source: a.rect, mag: Self.zoomFactor(a.variant))
                }
            }
            if interactive, let c = current, c.tool == .magnifier {
                Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .frame(width: c.rect.width, height: c.rect.height)
                    .position(x: c.rect.midX, y: c.rect.midY)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipped()
        .contentShape(Rectangle())
        .modifier(DrawGesture(enabled: interactive, tool: tool, variant: curVar, color: color,
                              lineWidth: lineWidth, current: $current, annos: $annos,
                              editingTextID: $editingTextID, onCrop: { applyCrop($0) },
                              onAdd: { redoStack.removeAll() }))
    }

    /// Crop the source region (display coords) out of the image as a small NSImage.
    private func cropImage(_ displayRect: CGRect) -> NSImage? {
        guard displayRect.width > 4, displayRect.height > 4,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width) / displaySize.width, sy = CGFloat(cg.height) / displaySize.height
        let px = CGRect(x: displayRect.minX * sx, y: displayRect.minY * sy,
                        width: displayRect.width * sx, height: displayRect.height * sy)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard px.width > 1, px.height > 1, let cropped = cg.cropping(to: px) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: px.width, height: px.height))
    }

    /// Pixels-per-display-point — converts on-screen distances to real pixels.
    private var pxScale: CGFloat {
        if let rep = image.representations.first, displaySize.width > 0 {
            return CGFloat(rep.pixelsWide) / displaySize.width
        }
        return image.size.width / max(displaySize.width, 1)
    }

    /// Spotlight holes (committed + in-progress), each carrying its rect and shape.
    private func spotlightHoles(interactive: Bool) -> [SpotHole] {
        var holes = annos.filter { $0.tool == .spotlight }
            .map { SpotHole(rect: $0.rect, ellipse: $0.variant == 1) }
        if interactive, let c = current, c.tool == .spotlight {
            holes.append(SpotHole(rect: c.rect, ellipse: c.variant == 1))
        }
        return holes
    }

    /// Text size by sub-option: Small / Medium / Large / XL (display points).
    private static func textSize(_ variant: Int) -> CGFloat {
        switch variant { case 0: return 18; case 2: return 38; case 3: return 56; default: return 26 }
    }

    @ViewBuilder
    private func textElement(_ a: Anno, interactive: Bool) -> some View {
        let size = Self.textSize(a.variant)
        if interactive, editingTextID == a.id {
            TextField("Text", text: bindingForText(a.id))
                .textFieldStyle(.plain)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(a.color).frame(width: 240)
                .position(x: a.start.x + 120, y: a.start.y)
                .onSubmit { editingTextID = nil }
        } else if !a.text.isEmpty {
            Text(a.text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(a.color).fixedSize()
                .position(x: a.start.x, y: a.start.y)
                .onTapGesture { if interactive { editingTextID = a.id } }
        }
    }

    private func bindingForText(_ id: UUID) -> Binding<String> {
        Binding(get: { annos.first(where: { $0.id == id })?.text ?? "" },
                set: { v in if let i = annos.firstIndex(where: { $0.id == id }) { annos[i].text = v } })
    }

    // MARK: Crop

    /// Aspect ratio (w/h) for the crop sub-option, or nil for free crop.
    private var cropAspect: CGFloat? {
        switch variants[.crop] ?? 0 {
        case 1: return 1
        case 2: return 16.0 / 9.0
        case 3: return 4.0 / 3.0
        default: return nil
        }
    }

    private func applyCrop(_ displayRect: CGRect) {
        var rect = displayRect
        // Constrain to the chosen aspect (centred inside the drawn rect).
        if let ar = cropAspect {
            var w = rect.width, h = rect.height
            if w / h > ar { w = h * ar } else { h = w / ar }
            rect = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        }
        guard rect.width > 8, rect.height > 8,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let sx = CGFloat(cg.width) / displaySize.width
        let sy = CGFloat(cg.height) / displaySize.height
        let px = CGRect(x: rect.minX * sx, y: rect.minY * sy,
                        width: rect.width * sx, height: rect.height * sy)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let cropped = cg.cropping(to: px) else { return }
        let newImg = NSImage(cgImage: cropped, size: NSSize(width: px.width, height: px.height))
        image = newImg
        displaySize = Self.fit(newImg.size)
        // Drop heavy caches; they rebuild lazily for the new (smaller) image.
        pixelated = nil
        blurred = nil
        annos.removeAll()
        redoStack.removeAll()
        current = nil
        tool = .arrow
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack {
            Text("\(image.size.width.rounded() == 0 ? 0 : Int(image.size.width)) × \(Int(image.size.height)) px")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(Backdrop.allCases) { b in
                    Button { backdrop = b } label: {
                        Label(b.label, systemImage: backdrop == b ? "checkmark" : "")
                    }
                }
            } label: {
                Label(backdrop == .none ? "Backdrop" : backdrop.label, systemImage: "photo.artframe")
            }
            .frame(width: 120)
            .help("Wrap the shot in a gradient backdrop")
            Button("Cancel") { onClose() }
            Button { if let i = render() { PinController.shared.pin(i) } } label: {
                Label("Pin", systemImage: "pin")
            }
            Button { saveToFile() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
            Button { addToShelf() } label: { Label("Add to Shelf", systemImage: "tray.and.arrow.down") }
            Button { copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @MainActor private func render() -> NSImage? {
        let r = ImageRenderer(content: styled(
            canvasContent(interactive: false).frame(width: displaySize.width, height: displaySize.height)))
        r.scale = max(image.size.width / displaySize.width, NSScreen.main?.backingScaleFactor ?? 2)
        return r.nsImage
    }

    private func copyToClipboard() {
        guard let img = render() else { return }
        AppSettings.shared.ignoreNextCopy = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        onClose()
    }

    private func addToShelf() {
        guard let img = render(),
              let (rel, thumb) = ShelfStore.shared.storeImage(img, prefix: "annot") else { return }
        ShelfStore.shared.add(ShelfItem(kind: .screenshot, title: "Annotated",
            preview: "Annotated \(Date().shortTime)", sourceApp: "Annotate",
            imageRelPath: rel, thumbRelPath: thumb))
        onClose()
    }

    private func saveToFile() {
        guard let img = render(), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot.png"
        if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
    }
}

// MARK: - Step badge

private struct StepBadge: View {
    let label: String
    let color: Color
    let diameter: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().stroke(Color.white, lineWidth: max(diameter * 0.06, 1.5))
            Text(label).font(.system(size: diameter * 0.5, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Redaction (pixelate / blur / solid)

/// One redaction region. `anno.variant`: 0=pixelate, 1=blur, 2=solid black.
private struct RedactView: View {
    let anno: Anno
    let pixelated: NSImage
    let blurred: NSImage
    let canvas: CGSize
    var body: some View {
        let r = anno.rect
        Group {
            if anno.variant == 2 {
                Rectangle().fill(Color.black)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
            } else {
                Image(nsImage: anno.variant == 1 ? blurred : pixelated).resizable()
                    .frame(width: canvas.width, height: canvas.height)
                    .mask(Rectangle().frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY))
            }
        }
    }
}

// MARK: - Spotlight

/// A spotlight hole — a region kept bright, optionally elliptical.
struct SpotHole { let rect: CGRect; let ellipse: Bool }

/// A dimming overlay over the whole canvas with "holes" punched out where the
/// spotlighted regions are (even-odd fill).
private struct SpotlightMask: View {
    let holes: [SpotHole]
    let canvas: CGSize
    var body: some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: canvas))
            for h in holes {
                if h.ellipse { p.addEllipse(in: h.rect) }
                else { p.addRoundedRect(in: h.rect, cornerSize: CGSize(width: 10, height: 10)) }
            }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .frame(width: canvas.width, height: canvas.height)
    }
}

// MARK: - Magnifier callout

/// A zoomed callout: the selected region rendered enlarged over the same spot,
/// with a white border (Apple-loupe style). Only the small crop is scaled, so
/// it's cheap on memory. Baked into exports.
private struct ZoomCallout: View {
    let crop: NSImage
    let source: CGRect      // display coordinates
    let mag: CGFloat
    var body: some View {
        let w = source.width * mag, h = source.height * mag
        Image(nsImage: crop).interpolation(.high).resizable()
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .position(x: source.midX, y: source.midY)
    }
}

// MARK: - Drawing gesture

private struct DrawGesture: ViewModifier {
    let enabled: Bool
    let tool: AnnoTool
    let variant: Int
    let color: Color
    let lineWidth: CGFloat
    @Binding var current: Anno?
    @Binding var annos: [Anno]
    @Binding var editingTextID: UUID?
    var onCrop: (CGRect) -> Void
    var onAdd: () -> Void

    private func make(_ start: CGPoint, _ end: CGPoint, points: [CGPoint] = []) -> Anno {
        Anno(tool: tool, start: start, end: end, color: color, lineWidth: lineWidth,
             variant: variant, points: points)
    }
    private func commit(_ a: Anno) { annos.append(a); onAdd() }

    /// Highlighter uses the freehand marker only in variant 0 (Marker).
    private var highlightFreehand: Bool { tool == .highlight && variant == 0 }

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        return AnyView(content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard tool != .text, tool != .step else { return }
                    if highlightFreehand {
                        if current == nil {
                            current = make(v.startLocation, v.location, points: [v.startLocation])
                        } else {
                            current?.points.append(v.location)
                            current?.end = v.location
                        }
                        return
                    }
                    if current == nil {
                        current = make(v.startLocation, v.location)
                    } else {
                        current?.end = v.location
                    }
                }
                .onEnded { v in
                    switch tool {
                    case .text:
                        let a = make(v.startLocation, v.startLocation)
                        annos.append(a); editingTextID = a.id; onAdd()
                    case .step:
                        commit(make(v.startLocation, v.startLocation))
                    case .highlight where highlightFreehand:
                        if var c = current {
                            if c.points.count < 2 { c.points.append(v.location) }  // a tap → short dab
                            commit(c); current = nil
                        }
                    case .crop:
                        if let c = current { onCrop(c.rect) }
                        current = nil
                    default:
                        if var c = current {
                            c.end = v.location
                            if c.tool == .arrow || c.rect.width > 4 || c.rect.height > 4 { commit(c) }
                            current = nil
                        }
                    }
                }
        ))
    }
}

// MARK: - Shapes

private struct AnnoShapeView: View {
    let anno: Anno
    var body: some View {
        switch anno.tool {
        case .box: boxView
        case .highlight: highlightView
        case .arrow:
            ArrowShape(start: anno.start, end: anno.end, style: anno.variant)
                .stroke(anno.color, style: StrokeStyle(lineWidth: anno.lineWidth, lineCap: .round, lineJoin: .round))
        default:
            EmptyView()
        }
    }

    // Box sub-styles: 0 outline · 1 filled · 2 rounded · 3 ellipse.
    @ViewBuilder private var boxView: some View {
        let r = anno.rect
        Group {
            switch anno.variant {
            case 1: Rectangle().fill(anno.color)
            case 2: RoundedRectangle(cornerRadius: max(anno.lineWidth * 2.5, 10))
                        .stroke(anno.color, lineWidth: anno.lineWidth)
            case 3: Ellipse().stroke(anno.color, lineWidth: anno.lineWidth)
            default: Rectangle().stroke(anno.color, lineWidth: anno.lineWidth)
            }
        }
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
    }

    // Highlight sub-styles: 0 marker (freehand multiply) · 1 block (translucent rect).
    @ViewBuilder private var highlightView: some View {
        if anno.variant == 1 {
            let r = anno.rect
            Rectangle().fill(anno.color.opacity(0.32))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .blendMode(.multiply)
        } else {
            MarkerStroke(points: anno.points.isEmpty ? [anno.start, anno.end] : anno.points)
                .stroke(anno.color.opacity(0.40),
                        style: StrokeStyle(lineWidth: max(anno.lineWidth * 4, 18),
                                           lineCap: .round, lineJoin: .round))
                .blendMode(.multiply)
        }
    }
}

/// A measuring ruler: a line with perpendicular end caps and a pixel-length label.
private struct RulerView: View {
    let anno: Anno
    let scale: CGFloat
    var body: some View {
        if anno.variant == 1 { boxRuler } else { lineRuler }
    }

    // Variant 0: a measured line with end caps.
    private var lineRuler: some View {
        let s = anno.start, e = anno.end
        let lenPx = Int((hypot(e.x - s.x, e.y - s.y) * scale).rounded())
        let mid = CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2)
        let dx = e.x - s.x, dy = e.y - s.y
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * 5, ny = dx / len * 5
        return ZStack {
            Path { p in
                p.move(to: s); p.addLine(to: e)
                p.move(to: CGPoint(x: s.x + nx, y: s.y + ny)); p.addLine(to: CGPoint(x: s.x - nx, y: s.y - ny))
                p.move(to: CGPoint(x: e.x + nx, y: e.y + ny)); p.addLine(to: CGPoint(x: e.x - nx, y: e.y - ny))
            }
            .stroke(anno.color, style: StrokeStyle(lineWidth: max(anno.lineWidth * 0.55, 1.5), lineCap: .round))
            label("\(lenPx) px").position(x: mid.x, y: mid.y - 13)
        }
    }

    // Variant 1: a dashed measuring box showing width × height in pixels.
    private var boxRuler: some View {
        let r = anno.rect
        let w = Int((r.width * scale).rounded()), h = Int((r.height * scale).rounded())
        return ZStack {
            Rectangle().stroke(anno.color, style: StrokeStyle(lineWidth: max(anno.lineWidth * 0.5, 1.3), dash: [5]))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
            label("\(w) × \(h) px").position(x: r.midX, y: r.minY - 11)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.78)))
            .foregroundStyle(.white)
    }
}

/// Freehand polyline for the highlighter marker.
private struct MarkerStroke: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

/// Arrow styles: 0 = arrowhead at end, 1 = plain line, 2 = double-headed.
private struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var style: Int = 0
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start); p.addLine(to: end)
        let len: CGFloat = 16
        func head(at tip: CGPoint, from origin: CGPoint) {
            let angle = atan2(tip.y - origin.y, tip.x - origin.x)
            let a1 = angle + .pi * 0.82, a2 = angle - .pi * 0.82
            p.move(to: tip); p.addLine(to: CGPoint(x: tip.x + cos(a1) * len, y: tip.y + sin(a1) * len))
            p.move(to: tip); p.addLine(to: CGPoint(x: tip.x + cos(a2) * len, y: tip.y + sin(a2) * len))
        }
        if style != 1 { head(at: end, from: start) }     // arrow + double
        if style == 2 { head(at: start, from: end) }       // double only
        return p
    }
}

// MARK: - Pixelate helper

enum AnnotationRender {
    // One shared context — each `CIContext()` allocates a sizeable Metal cache.
    private static let ctx = CIContext(options: [.cacheIntermediates: false])

    static func pixelate(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter.pixellate()
        filter.inputImage = ci
        filter.scale = 16
        filter.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        guard let out = filter.outputImage?.cropped(to: ci.extent),
              let outCG = ctx.createCGImage(out, from: ci.extent) else { return nil }
        return NSImage(cgImage: outCG, size: image.size)
    }

    static func gaussianBlur(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        // Clamp first so the blur doesn't darken/feather the edges.
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ci.clampedToExtent()
        filter.radius = 12
        guard let out = filter.outputImage?.cropped(to: ci.extent),
              let outCG = ctx.createCGImage(out, from: ci.extent) else { return nil }
        return NSImage(cgImage: outCG, size: image.size)
    }
}
