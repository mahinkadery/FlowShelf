import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Model

enum AnnoTool: String, CaseIterable, Identifiable {
    case arrow, box, highlight, blur, text
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.left"
        case .box: return "rectangle"
        case .highlight: return "highlighter"
        case .blur: return "drop.degreesign"
        case .text: return "textformat"
        }
    }
    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .highlight: return "Highlight"
        case .blur: return "Blur"
        case .text: return "Text"
        }
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
        // Reuse a single editor window.
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
        // Drop back to menu-bar agent unless the dashboard is still up.
        if DashboardWindowController.shared.isVisible == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Editor view

struct AnnotationEditorView: View {
    let image: NSImage
    var onClose: () -> Void

    @State private var tool: AnnoTool = .arrow
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var annos: [Anno] = []
    @State private var current: Anno?
    @State private var editingTextID: UUID?

    private let pixelated: NSImage
    private let displaySize: CGSize

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        self.pixelated = AnnotationRender.pixelate(image) ?? image
        // Fit the image into a sensible editing size, preserving aspect.
        let maxW: CGFloat = 1000, maxH: CGFloat = 680
        let s = image.size
        let scale = min(1, min(maxW / max(s.width, 1), maxH / max(s.height, 1)))
        displaySize = CGSize(width: max(s.width * scale, 200), height: max(s.height * scale, 150))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView([.horizontal, .vertical]) {
                canvasContent(interactive: true)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
            Divider()
            actionBar
        }
        .frame(minWidth: displaySize.width + 60, minHeight: displaySize.height + 130)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            ForEach(AnnoTool.allCases) { t in
                Button { tool = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.system(size: 14))
                        Text(t.label).font(.system(size: 9))
                    }
                    .frame(width: 50, height: 38)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(tool == t ? Color.accentColor.opacity(0.2) : Color.clear))
                    .foregroundStyle(tool == t ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 30)
            ColorPicker("", selection: $color).labelsHidden().frame(width: 40)
            VStack(spacing: 1) {
                Text("Width").font(.system(size: 9)).foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 2...12).frame(width: 90)
            }
            Spacer()
            Button { if !annos.isEmpty { annos.removeLast() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }.disabled(annos.isEmpty)
            Button(role: .destructive) { annos.removeAll() } label: {
                Label("Clear", systemImage: "trash")
            }.disabled(annos.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvasContent(interactive: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable()
                .frame(width: displaySize.width, height: displaySize.height)

            // Blur regions: show the pixelated copy masked to each blur rect.
            ForEach(annos.filter { $0.tool == .blur }) { a in
                Image(nsImage: pixelated).resizable()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .mask(
                        Rectangle()
                            .frame(width: a.rect.width, height: a.rect.height)
                            .position(x: a.rect.midX, y: a.rect.midY)
                    )
            }

            // Shapes (arrow/box/highlight).
            ForEach(annos.filter { $0.tool == .arrow || $0.tool == .box || $0.tool == .highlight }) { a in
                AnnoShapeView(anno: a)
            }
            if let current, current.tool != .text {
                AnnoShapeView(anno: current)
            }

            // Text.
            ForEach(annos.filter { $0.tool == .text }) { a in
                textElement(a, interactive: interactive)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipped()
        .contentShape(Rectangle())
        .modifier(DrawGesture(enabled: interactive, tool: tool, color: color, lineWidth: lineWidth,
                              current: $current, annos: $annos, editingTextID: $editingTextID))
    }

    @ViewBuilder
    private func textElement(_ a: Anno, interactive: Bool) -> some View {
        if interactive, editingTextID == a.id {
            TextField("Text", text: bindingForText(a.id))
                .textFieldStyle(.plain)
                .font(.system(size: max(a.lineWidth * 3.5, 14), weight: .semibold))
                .foregroundStyle(a.color)
                .frame(width: 220)
                .position(x: a.start.x + 110, y: a.start.y)
                .onSubmit { editingTextID = nil }
        } else if !a.text.isEmpty {
            Text(a.text)
                .font(.system(size: max(a.lineWidth * 3.5, 14), weight: .semibold))
                .foregroundStyle(a.color)
                .fixedSize()
                .position(x: a.start.x, y: a.start.y)
                .onTapGesture { if interactive { editingTextID = a.id } }
        }
    }

    private func bindingForText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { annos.first(where: { $0.id == id })?.text ?? "" },
            set: { v in if let i = annos.firstIndex(where: { $0.id == id }) { annos[i].text = v } }
        )
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack {
            Text("\(annos.count) annotation\(annos.count == 1 ? "" : "s")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { onClose() }
            Button { saveToFile() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
            Button { addToShelf() } label: { Label("Add to Shelf", systemImage: "tray.and.arrow.down") }
            Button { copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @MainActor private func render() -> NSImage? {
        let renderer = ImageRenderer(content:
            canvasContent(interactive: false)
                .frame(width: displaySize.width, height: displaySize.height)
        )
        renderer.scale = max(image.size.width / displaySize.width, NSScreen.main?.backingScaleFactor ?? 2)
        return renderer.nsImage
    }

    private func copyToClipboard() {
        guard let img = render() else { return }
        let pb = NSPasteboard.general
        AppSettings.shared.ignoreNextCopy = true
        pb.clearContents()
        pb.writeObjects([img])
        onClose()
    }

    private func addToShelf() {
        guard let img = render(),
              let (rel, thumb) = ShelfStore.shared.storeImage(img, prefix: "annot") else { return }
        ShelfStore.shared.add(ShelfItem(
            kind: .screenshot, title: "Annotated", preview: "Annotated \(Date().shortTime)",
            sourceApp: "Annotate", imageRelPath: rel, thumbRelPath: thumb))
        onClose()
    }

    private func saveToFile() {
        guard let img = render(),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}

// MARK: - Drawing gesture (factored so export can omit it)

private struct DrawGesture: ViewModifier {
    let enabled: Bool
    let tool: AnnoTool
    let color: Color
    let lineWidth: CGFloat
    @Binding var current: Anno?
    @Binding var annos: [Anno]
    @Binding var editingTextID: UUID?

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard tool != .text else { return }
                        if current == nil {
                            current = Anno(tool: tool, start: v.startLocation, end: v.location,
                                           color: color, lineWidth: lineWidth)
                        } else {
                            current?.end = v.location
                        }
                    }
                    .onEnded { v in
                        if tool == .text {
                            let a = Anno(tool: .text, start: v.startLocation, end: v.startLocation,
                                         color: color, lineWidth: lineWidth)
                            annos.append(a)
                            editingTextID = a.id
                            return
                        }
                        if var c = current {
                            c.end = v.location
                            // Ignore stray taps for shapes that need an area.
                            if c.tool == .arrow || c.rect.width > 4 || c.rect.height > 4 {
                                annos.append(c)
                            }
                            current = nil
                        }
                    }
            )
        } else {
            content
        }
    }
}

// MARK: - Shapes

private struct AnnoShapeView: View {
    let anno: Anno
    var body: some View {
        switch anno.tool {
        case .box:
            Rectangle().stroke(anno.color, lineWidth: anno.lineWidth)
                .frame(width: anno.rect.width, height: anno.rect.height)
                .position(x: anno.rect.midX, y: anno.rect.midY)
        case .highlight:
            Rectangle().fill(anno.color.opacity(0.30))
                .frame(width: anno.rect.width, height: anno.rect.height)
                .position(x: anno.rect.midX, y: anno.rect.midY)
        case .arrow:
            ArrowShape(start: anno.start, end: anno.end)
                .stroke(anno.color, style: StrokeStyle(lineWidth: anno.lineWidth, lineCap: .round, lineJoin: .round))
        default:
            EmptyView()
        }
    }
}

private struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start); p.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let len: CGFloat = 16
        let a1 = angle + .pi * 0.82, a2 = angle - .pi * 0.82
        p.move(to: end); p.addLine(to: CGPoint(x: end.x + cos(a1) * len, y: end.y + sin(a1) * len))
        p.move(to: end); p.addLine(to: CGPoint(x: end.x + cos(a2) * len, y: end.y + sin(a2) * len))
        return p
    }
}

// MARK: - Pixelate helper

enum AnnotationRender {
    static func pixelate(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter.pixellate()
        filter.inputImage = ci
        filter.scale = 16
        filter.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        let ctx = CIContext()
        guard let outCG = ctx.createCGImage(out, from: ci.extent) else { return nil }
        return NSImage(cgImage: outCG, size: image.size)
    }
}
