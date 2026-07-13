import SwiftUI
import AppKit
import CoreVideo
import CoreImage
import ScreenCaptureKit

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var targeted = false
    /// A drag is in flight somewhere on screen — show the drop invitation.
    @Published var dropReady = false
    /// Size of the physical notch (the visible collapsed pill). Set by controller.
    @Published var collapsedSize = CGSize(width: 200, height: 32)
    /// Size of the open panel.
    let expandedSize = CGSize(width: 600, height: 185)

    /// The *interactive* area when collapsed — a bit wider and taller than the
    /// visible pill so it's easy to drag a file into (and to swipe down from).
    var triggerSize: CGSize {
        CGSize(width: collapsedSize.width + 44, height: collapsedSize.height + 34)
    }
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

    /// The open card sizes itself to its content — a couple of items make a small
    /// card, a full shelf grows toward the maximum.
    private var expandedCardSize: CGSize {
        let stripH = model.collapsedSize.height
        guard !recent.isEmpty else { return CGSize(width: 320, height: stripH + 104) }
        let n = CGFloat(recent.count)
        let tiles = n * 74 + (n - 1) * 10
        let width = min(model.expandedSize.width, max(tiles + 44, model.collapsedSize.width + 40))
        return CGSize(width: width, height: stripH + 118)
    }

    /// On hover the invisible notch reveals itself as a rounded glass bar —
    /// the "I'm here, tap me" cue — without opening.
    private var peekSize: CGSize {
        CGSize(width: model.collapsedSize.width + 18, height: model.collapsedSize.height + 11)
    }

    private var pillSize: CGSize {
        if model.expanded { return expandedCardSize }
        return (hovering || model.targeted) ? peekSize : model.collapsedSize
    }

    /// The interactive (hover/drag/drop) frame — larger than the pill when closed.
    private var frameSize: CGSize { model.expanded ? model.expandedSize : model.triggerSize }
    private var shape: NotchShape {
        NotchShape(topRadius: model.expanded ? 12 : 7, bottomRadius: model.expanded ? 26 : 12)
    }

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            pill
        }
        .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        // Drag/drop is handled at the AppKit level in NotchHostingView.
        .flowExpand(model.expanded)
    }

    private var pill: some View {
        ZStack(alignment: .top) {
            // LIVE refraction lens underneath — always present (never gated on
            // `expanded`) so the view is not recreated and its capture stream
            // stays warm; recreating it cold-started the stream, which was the
            // brief flicker of raw layers on open. It is fully hidden behind the
            // solid black card until the card's bottom fade reveals it.
            GlassBackground()

            // The black card: solid into the notch, thinning to smoke, and
            // alpha-fading to nothing over the live glass band.
            cardLayer
        }
        .frame(width: pillSize.width, height: pillSize.height)
        // Specular rim — the "glass edge" that makes a black surface read as
        // glass: crisp light along the top, falling to a dark lower edge.
        .overlay(
            shape.stroke(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.30), location: 0),
                    .init(color: .white.opacity(0.07), location: 0.35),
                    .init(color: .black.opacity(0.30), location: 1),
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
            .opacity(model.expanded || hovering || model.targeted ? 1 : 0)
        )
        .foregroundStyle(.white)
        // NOTE: no .shadow here — a shadow forces the subtree into an offscreen
        // pass, which freezes the live Liquid Glass backdrop into a static frost.
        .animation(FlowMotion.hoverScale, value: hovering)
        .animation(FlowMotion.state, value: model.targeted)
        .onHover { hovering = $0 }
        // Tap the bar to open; tap again (outside tiles) to close.
        .onTapGesture {
            model.expanded.toggle()
        }
    }

    /// The black portion of the card: clipped to the notch silhouette and
    /// alpha-faded toward the bottom. Safe to mask — the live glass is a
    /// sibling underneath, not inside this subtree.
    private var cardLayer: some View {
        ZStack(alignment: .top) {
            // Solid black fill; the mask below is the single thing that eases it
            // into the glass, so there is no doubled-up gradient seam.
            Color.black

            if model.expanded {
                expandedContent
                    .frame(width: expandedCardSize.width, height: expandedCardSize.height, alignment: .top)
                    // Emerge on open, plain fade on close — no separate zoom-out
                    // "layer" peeling off during the collapse.
                    .transition(.asymmetric(insertion: .flowEmergeLight, removal: .opacity))
            } else {
                VStack {
                    Spacer()
                    Capsule().fill(.white.opacity((hovering || model.targeted) ? 0.55 : 0.14))
                        .frame(width: 26, height: 3).padding(.bottom, 3)
                }
            }
        }
        .clipShape(shape)
        // One long, smooth ramp from solid black to fully clear so the black and
        // the glass read as a single continuous surface, not two stacked zones.
        .mask(
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: model.expanded ? 0.44 : 1),
                .init(color: .black.opacity(0.85), location: model.expanded ? 0.60 : 1),
                .init(color: .black.opacity(0.6), location: model.expanded ? 0.72 : 1),
                .init(color: .black.opacity(0.34), location: model.expanded ? 0.83 : 1),
                .init(color: .black.opacity(0.12), location: model.expanded ? 0.93 : 1),
                .init(color: .black.opacity(0.0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Reserve the camera-notch strip at the very top so nothing hides
            // behind it.
            Color.clear.frame(height: model.collapsedSize.height)

            ZStack {
                if recent.isEmpty {
                    dropInvitation
                } else {
                    // Plain wheel scrolling pans the row — no Shift needed.
                    HWheelScroll {
                        HStack(spacing: 10) {
                            ForEach(recent) {
                                NotchTile(item: $0).transition(.flowEmergeLight)
                            }
                        }
                        .animation(FlowMotion.listChange, value: recent.map(\.id))
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 12)
        }
        // While a drag is in flight, an inset dashed ring invites the drop
        // (accent-tinted once the drag is actually over the shelf).
        .overlay {
            if model.dropReady, !model.targeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.22),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .padding(.horizontal, 9)
                    .padding(.top, model.collapsedSize.height + 3)
                    .padding(.bottom, 7)
                    .transition(.opacity)
            }
        }
        .animation(FlowMotion.state, value: model.dropReady)
    }

    /// Empty-shelf / drag-in-flight invitation.
    private var dropInvitation: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(model.targeted ? 0.95 : 0.55))
            Text(model.targeted ? "Release to shelve" : "Drop files, images, or text")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(model.targeted ? 0.95 : 0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A horizontal scroller that pans with a **plain** mouse wheel — no Shift
/// required. Vertical wheel/trackpad deltas are translated into horizontal
/// travel and clamped to the content.
private struct HWheelScroll<Content: View>: NSViewRepresentable {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> WheelScrollView {
        let sv = WheelScrollView()
        sv.drawsBackground = false
        sv.hasHorizontalScroller = false
        sv.hasVerticalScroller = false
        sv.horizontalScrollElasticity = .none
        sv.verticalScrollElasticity = .none
        let host = NSHostingView(rootView: content)
        host.frame.size = host.fittingSize
        sv.documentView = host
        return sv
    }

    func updateNSView(_ sv: WheelScrollView, context: Context) {
        guard let host = sv.documentView as? NSHostingView<Content> else { return }
        host.rootView = content
        host.frame.size = host.fittingSize
    }
}

final class WheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX
        guard abs(dy) > abs(dx), let doc = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let step = event.hasPreciseScrollingDeltas ? dy : dy * 9
        var origin = contentView.bounds.origin
        let maxX = max(0, doc.frame.width - contentView.bounds.width)
        origin.x = min(max(0, origin.x - step), maxX)
        contentView.setBoundsOrigin(origin)
        reflectScrolledClipView(contentView)
    }
}

/// The glass base layer the black gradient fades into.
///
/// This is the one piece that makes the transparent bottom actually *lens* the
/// desktop, the way Droppy does it: `NSGlassEffectView` only refracts content
/// **inside its own window**, so we capture the live desktop behind the notch
/// (ScreenCaptureKit) and pin it as an in-window backdrop *underneath* the glass.
/// Apple's Liquid Glass then does the refraction / edge-curl / chroma for free.
/// The card's alpha fade above reveals it only at the bottom.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GlassStack() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? GlassStack)?.teardown()
    }
}

private final class GlassStack: NSView {
    // Capture
    private var stream: SCStream?
    private var output: StreamOutput?
    private let lock = NSLock()
    private var band: CGImage?
    private var displayLink: CADisplayLink?
    private let bandHeightPoints: CGFloat = 340
    private var streaming = false
    private var startingStream = false
    /// Only capture/render once the card is tall enough to actually reveal glass —
    /// below this it is collapsed/peeking and fully covered by the black card.
    private let activeHeight: CGFloat = 90

    // Core Image displacement lens. Rendering to a CGImage (not a live CAMetal
    // layer) means this view composites BELOW the SwiftUI black card, so the
    // card's alpha-fade reveals it — exactly like the old frosted GlassBackground,
    // but now bending the real desktop instead of frosting it.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let kernel: CIKernel? = GlassStack.makeKernel()
    private let clipMask = CAShapeLayer()
    private let bottomRadius: CGFloat = 26
    private var lastSize: CGSize = .zero
    private var lastResize: CFTimeInterval = 0    // when the card last changed size
    private var lastRender: CFTimeInterval = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resize
        layer?.mask = clipMask          // clip to the notch's lower silhouette
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // Warm the capture only while the card is open; stop (but keep the last
        // frame) once it collapses, so we neither burn energy capturing behind a
        // covered view nor cold-start on the next open. The render loop is paused
        // outright when collapsed so there are no idle 60fps wakeups all day. The
        // stale last frame is prevented from peeking through the notch's concave
        // corners by clipping to the exact notch silhouette (`clipMask`), so no
        // separate hide toggle is needed (that toggle popped mid-animation).
        let active = window != nil && bounds.height >= activeHeight
        if bounds.size != lastSize {
            lastSize = bounds.size
            lastResize = CACurrentMediaTime()        // mark the card as animating
            CATransaction.begin(); CATransaction.setDisableActions(true)
            clipMask.path = notchPath(in: bounds, top: 12, bottom: bottomRadius).cgPath
            CATransaction.commit()
        }
        displayLink?.isPaused = !active
        if active { startCapture() } else { stopCapture() }
    }

    /// The FULL Dynamic-Island silhouette — concave top corners + rounded bottom —
    /// matching NotchShape exactly (in AppKit's y-up space) so the refracted image
    /// can never extend past the black card into the concave corners or the sides.
    private func notchPath(in rect: NSRect, top tr0: CGFloat, bottom br0: CGFloat) -> NSBezierPath {
        let w = rect.width, h = rect.height
        let tr = min(tr0, w / 2), br = min(br0, w / 2)
        let p = NSBezierPath()
        // Quadratic → cubic helper (NSBezierPath has no native quad curve).
        func quad(from a: NSPoint, to b: NSPoint, ctrl q: NSPoint) {
            let c1 = NSPoint(x: a.x + 2.0/3.0 * (q.x - a.x), y: a.y + 2.0/3.0 * (q.y - a.y))
            let c2 = NSPoint(x: b.x + 2.0/3.0 * (q.x - b.x), y: b.y + 2.0/3.0 * (q.y - b.y))
            p.curve(to: b, controlPoint1: c1, controlPoint2: c2)
        }
        var cur = NSPoint(x: 0, y: h)
        p.move(to: cur)
        quad(from: cur, to: NSPoint(x: tr, y: h - tr), ctrl: NSPoint(x: tr, y: h)); cur = NSPoint(x: tr, y: h - tr)   // concave top-left
        p.line(to: NSPoint(x: tr, y: br)); cur = NSPoint(x: tr, y: br)
        quad(from: cur, to: NSPoint(x: tr + br, y: 0), ctrl: NSPoint(x: tr, y: 0)); cur = NSPoint(x: tr + br, y: 0)   // bottom-left
        p.line(to: NSPoint(x: w - tr - br, y: 0)); cur = NSPoint(x: w - tr - br, y: 0)
        quad(from: cur, to: NSPoint(x: w - tr, y: br), ctrl: NSPoint(x: w - tr, y: 0)); cur = NSPoint(x: w - tr, y: br)   // bottom-right
        p.line(to: NSPoint(x: w - tr, y: h - tr)); cur = NSPoint(x: w - tr, y: h - tr)
        quad(from: cur, to: NSPoint(x: w, y: h), ctrl: NSPoint(x: w - tr, y: h))   // concave top-right
        p.close()
        return p
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            guard displayLink == nil else { return }
            let dl = displayLink(target: self, selector: #selector(tick))
            dl.isPaused = true               // layout() resumes it while open
            dl.add(to: .current, forMode: .common)
            displayLink = dl
        } else {
            teardown()
        }
    }

    func teardown() {
        displayLink?.invalidate(); displayLink = nil
        stopCapture()
        lock.lock(); band = nil; lock.unlock()
    }

    // MARK: Capture

    private func startCapture() {
        guard !streaming, !startingStream,
              let screen = window?.screen ?? NSScreen.main else { return }
        startingStream = true
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let scale = screen.backingScaleFactor

        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID })
                        ?? content.displays.first else { await MainActor.run { self.startingStream = false }; return }
                let myPID = ProcessInfo.processInfo.processIdentifier
                let mine = content.windows.filter { $0.owningApplication?.processID == myPID }
                let filter = SCContentFilter(display: display, excludingWindows: mine)

                let band = CGRect(x: 0, y: 0, width: CGFloat(display.width),
                                  height: min(self.bandHeightPoints, CGFloat(display.height)))
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = band
                cfg.width = Int(band.width * scale)
                cfg.height = Int(band.height * scale)
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.showsCursor = false
                cfg.queueDepth = 3
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)   // 30fps is plenty
                cfg.scalesToFit = false

                let out = StreamOutput { [weak self] pb in self?.ingest(pb) }
                let stream = SCStream(filter: filter, configuration: cfg, delegate: out)
                try stream.addStreamOutput(out, type: .screen,
                                           sampleHandlerQueue: DispatchQueue(label: "flowshelf.notch.capture"))
                try await stream.startCapture()
                await MainActor.run {
                    self.startingStream = false
                    // Bail if we were asked to stop while starting up.
                    guard self.window != nil, self.bounds.height >= self.activeHeight else {
                        stream.stopCapture { _ in }; return
                    }
                    self.stream = stream; self.output = out; self.streaming = true
                }
            } catch {
                await MainActor.run { self.startingStream = false }
                NSLog("Notch glass: capture unavailable: \(error)")
            }
        }
    }

    /// Stop the stream but keep the last frame, so re-opening shows the lens
    /// instantly (very briefly stale) instead of flickering through an empty view.
    private func stopCapture() {
        guard streaming else { return }
        streaming = false
        stream?.stopCapture { _ in }
        stream = nil; output = nil
    }

    private func ingest(_ pb: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        lock.lock(); band = cg; lock.unlock()
    }

    /// Crop the captured desktop to what sits behind this view, run it through the
    /// displacement lens, and show the result. No white wash, no frost — the
    /// desktop is genuinely bent at the bottom edge.
    @objc private func tick() {
        guard let window, let kernel, bounds.width > 2, bounds.height >= activeHeight else { return }
        // Skip rendering while the card is actively springing (resized in the last
        // ~60ms) — the per-frame Core Image work on the main thread is what made
        // the open/close feel laggy; the lens settles in the moment motion stops.
        let now = CACurrentMediaTime()
        if now - lastResize < 0.06 { return }
        if now - lastRender < 1.0/30.0 { return }        // 30fps is plenty
        lastRender = now
        lock.lock(); let b = band; lock.unlock()
        guard let b, let screen = window.screen ?? NSScreen.main else { return }

        let s = window.backingScaleFactor
        let scr = window.convertToScreen(convert(bounds, to: nil))   // AppKit, bottom-left
        // Distance of this view's top from the DISPLAY's top edge (works on any
        // monitor, including ones offset vertically in the global layout).
        let topLeftY = screen.frame.maxY - scr.maxY

        var cx = (scr.minX - screen.frame.minX) * s
        var cy = topLeftY * s
        let cw = bounds.width * s
        let ch = bounds.height * s
        let bw = CGFloat(b.width), bh = CGFloat(b.height)
        guard cw > 1, ch > 1, cw <= bw, ch <= bh else { return }
        cx = max(0, min(cx, bw - cw)); cy = max(0, min(cy, bh - ch))
        guard let crop = b.cropping(to: CGRect(x: cx, y: cy, width: cw, height: ch)) else { return }

        // clampedToExtent so the displacement never samples past the crop edge
        // (that produced the harsh corner fringe and the faint horizontal streak).
        let src = CIImage(cgImage: crop).clampedToExtent()
        let extent = CGRect(x: 0, y: 0, width: cw, height: ch)
        let w = Float(cw), h = Float(ch)
        let radius = Float(bottomRadius * s)
        let edge = Float(min(ch, 80 * s))       // bevel spans the visible bottom band
        let strength = Float(15 * s)            // inward pull at the rim (the bend)
        let chroma = Float(0.9 * s)             // prismatic fringe — a whisper, not a rainbow
        let margin = CGFloat(strength + chroma + 2)
        let out = kernel.apply(extent: extent,
                               roiCallback: { _, r in r.insetBy(dx: -margin, dy: -margin) },
                               arguments: [src, w, h, radius, edge, strength, chroma])
        guard let out, let cg = ciContext.createCGImage(out, from: extent) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = cg
        layer?.contentsScale = s
        CATransaction.commit()
    }

    // MARK: Lens kernel

    /// Core Image general kernel: pulls the sample coordinate inward along the
    /// notch's edge field, strongest right at the rim → straight lines behind
    /// visibly curve under the BOTTOM edge and corners. The refraction is weighted
    /// by how downward-facing the edge is (`bottomBias`), so the vertical left/
    /// right sides stay clean — no rainbow "bars" down the sides.
    private static func makeKernel() -> CIKernel? {
        let source = """
        kernel vec4 notchLens(sampler src, float w, float h, float radius, float edge, float strength, float chroma) {
            vec2 d = destCoord();
            vec2 c = vec2(w, h) * 0.5;
            vec2 p = d - c;
            vec2 bx = c;
            vec2 q = abs(p) - bx + vec2(radius);
            float sdf = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
            float inside = -sdf;                               // >0 inside the notch
            float t = 1.0 - smoothstep(0.0, edge, inside);     // 1 at rim, 0 inward
            float bevel = t * t * (3.0 - 2.0 * t);
            // TRUE rounded-box outward normal: axis-aligned along the flat edges,
            // and a proper 45deg diagonal at the rounded corners. (normalize(p)
            // was wrong for a wide box — it pointed sideways at the corners, which
            // is why the corners didn't curve and the sides fringed.)
            vec2 sg = sign(p);
            vec2 n;
            if (min(q.x, q.y) > 0.0) {
                n = normalize(q) * sg;                         // corner: radial
            } else {
                n = (q.x > q.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y);  // edge: axis
            }
            // Refract only where the edge faces downward (bottom + bottom corners);
            // the vertical sides face sideways (n.y ~ 0) so they get nothing.
            float bottomBias = smoothstep(0.20, 0.72, -n.y);
            float k = bevel * bottomBias;
            vec2 disp = -n * (k * strength);                   // pull inward at rim
            vec2 ca = -n * (k * chroma);
            vec4 col;
            col.r = sample(src, samplerTransform(src, d + disp + ca)).r;
            col.g = sample(src, samplerTransform(src, d + disp)).g;
            col.b = sample(src, samplerTransform(src, d + disp - ca)).b;
            col.a = 1.0;
            return col;
        }
        """
        return CIKernel(source: source)
    }

    private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
        private let onFrame: (CVPixelBuffer) -> Void
        init(onFrame: @escaping (CVPixelBuffer) -> Void) { self.onFrame = onFrame }
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                    of type: SCStreamOutputType) {
            guard type == .screen, sampleBuffer.isValid,
                  let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            if let attach = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
               let raw = attach.first?[.status] as? Int,
               let status = SCFrameStatus(rawValue: raw), status != .complete { return }
            onFrame(pb)
        }
        func stream(_ stream: SCStream, didStopWithError error: Error) {
            NSLog("Notch glass: stream stopped: \(error)")
        }
    }
}

/// A Finder-like tile in the expanded notch: real file icon or image thumbnail
/// with the name captioned underneath. Click to copy, drag out, hover to reveal
/// a remove button.
private struct NotchTile: View {
    let item: ShelfItem
    @ObservedObject private var store = ShelfStore.shared
    @State private var hovering = false

    private let thumbSide: CGFloat = 58
    private let tileWidth: CGFloat = 74

    /// The glass-edge highlight: bright top rim falling into a shaded bottom.
    private var rim: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(hovering ? 0.50 : 0.32), location: 0),
            .init(color: .white.opacity(0.08), location: 0.4),
            .init(color: .black.opacity(0.25), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Glass chip on black: a light lift-tint + the specular rim
                    // sell the effect without a per-tile blur layer (7 of those
                    // made opening stutter on 60Hz panels).
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    thumb
                }
                    .frame(width: thumbSide, height: thumbSide)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(rim, lineWidth: 1))

                if hovering {
                    Button { store.remove(item.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(.black.opacity(0.85)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .offset(x: 5, y: -5)
                    .transition(.flowPop)
                }
            }

            Text(caption)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: tileWidth)
        }
        .scaleEffect(hovering ? 1.06 : 1)
        .flowHover($hovering)
        .contentShape(Rectangle())
        .onTapGesture { ItemActions.copyToPasteboard(item) }
        .onDrag { DragDrop.provider(for: item) }
        .help(item.preview)
    }

    @ViewBuilder private var thumb: some View {
        if item.hasImage, let t = store.thumbnail(for: item) {
            Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                .frame(width: thumbSide, height: thumbSide)
        } else if item.kind == .file, let path = item.filePath {
            // The real Finder icon on the glass chip — instantly recognizable.
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().aspectRatio(contentMode: .fit)
                .padding(6)
        } else if item.kind == .link {
            Image(systemName: "link").font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        } else {
            // Text / OCR: a mini "note" with the first lines visible.
            Text(item.preview)
                .font(.system(size: 6.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(5)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var caption: String {
        switch item.kind {
        case .file: return item.title
        case .link: return URL(string: item.text ?? "")?.host ?? item.title
        case .image, .screenshot: return item.title
        default: return item.preview.firstLine(max: 20)
        }
    }
}
