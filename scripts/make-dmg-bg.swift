import AppKit

// Compose the DMG background: the supplied gradient (Resources/dmg-bg-base.png)
// + the FlowShelf wordmark, tagline, an arrow, and a "drag to install" pill.
// The two draggable icons (FlowShelf.app + Applications) are placed by Finder, so
// we leave the center band empty for them.

let W: CGFloat = 1448, H: CGFloat = 1086          // 2x of a 724x543 pt window
let amber = NSColor(srgbRed: 0.97, green: 0.66, blue: 0.15, alpha: 1)
func fromTop(_ t: CGFloat) -> CGFloat { H - t }   // convert top-origin → bottom-left

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

let canvas = NSImage(size: NSSize(width: W, height: H))
canvas.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

// 1. Base gradient (or a dark fallback).
if let base = NSImage(contentsOfFile: "Resources/dmg-bg-base.png") {
    base.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
} else {
    NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
}

// Helpers ----------------------------------------------------------------
func drawText(_ s: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = s.size(withAttributes: attrs)
    s.draw(at: NSPoint(x: centerX - size.width / 2, y: fromTop(top) - size.height),
           withAttributes: attrs)
}
func tinted(_ symbol: String, _ color: NSColor, pt: CGFloat) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
}

// 2. Title: logo + "Flow" (white) + "Shelf" (amber), centered near the top.
let titleFont = NSFont.systemFont(ofSize: 70, weight: .bold)
let flow = "Flow", shelf = "Shelf"
let flowW = flow.size(withAttributes: [.font: titleFont]).width
let shelfW = shelf.size(withAttributes: [.font: titleFont]).width
let logoSize: CGFloat = 92, logoGap: CGFloat = 18
let groupW = logoSize + logoGap + flowW + shelfW
var x = (W - groupW) / 2
let titleTop: CGFloat = 92
if let logo = NSImage(contentsOfFile: "Resources/AppIcon.png") {
    logo.draw(in: NSRect(x: x, y: fromTop(titleTop) - logoSize + 8, width: logoSize, height: logoSize))
}
x += logoSize + logoGap
let titleH = flow.size(withAttributes: [.font: titleFont]).height
flow.draw(at: NSPoint(x: x, y: fromTop(titleTop) - titleH), withAttributes: [.font: titleFont, .foregroundColor: NSColor.white])
x += flowW
shelf.draw(at: NSPoint(x: x, y: fromTop(titleTop) - titleH), withAttributes: [.font: titleFont, .foregroundColor: amber])

// 3. Tagline.
drawText("Organize everything. Find anything.",
         font: .systemFont(ofSize: 34, weight: .regular),
         color: NSColor(calibratedWhite: 0.72, alpha: 1), centerX: W / 2, top: 196)

// 4. Arrow between the (Finder-placed) icons, at the vertical centre.
let ay = fromTop(543)
NSColor(calibratedWhite: 0.78, alpha: 0.85).setStroke()
let shaft = NSBezierPath(); shaft.lineWidth = 9; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 672, y: ay)); shaft.line(to: NSPoint(x: 786, y: ay)); shaft.stroke()
let head = NSBezierPath(); head.lineWidth = 9; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: 752, y: ay + 30)); head.line(to: NSPoint(x: 788, y: ay)); head.line(to: NSPoint(x: 752, y: ay - 30)); head.stroke()

// 5. "Drag to install" pill near the bottom.
let pillW: CGFloat = 660, pillH: CGFloat = 120
let pillRect = NSRect(x: (W - pillW) / 2, y: fromTop(900) - pillH, width: pillW, height: pillH)
let pill = NSBezierPath(roundedRect: pillRect, xRadius: 24, yRadius: 24)
NSColor(calibratedWhite: 0.0, alpha: 0.28).setFill(); pill.fill()
NSColor(calibratedWhite: 1, alpha: 0.14).setStroke(); pill.lineWidth = 2; pill.stroke()
if let mouse = tinted("computermouse.fill", amber, pt: 48) {
    mouse.draw(in: NSRect(x: pillRect.minX + 46, y: pillRect.midY - 30, width: 44, height: 60))
}
let pillText: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1)]
let l1 = "Drag FlowShelf to your Applications folder", l2 = "to install"
l1.draw(at: NSPoint(x: pillRect.minX + 130, y: pillRect.midY + 4), withAttributes: pillText)
l2.draw(at: NSPoint(x: pillRect.minX + 130, y: pillRect.midY - 40), withAttributes: pillText)

canvas.unlockFocus()
// JPEG keeps a smooth gradient background tiny (a PNG re-encode balloons to ~20MB).
if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) {
    try? jpg.write(to: URL(fileURLWithPath: out))
    print("make-dmg-bg: wrote \(out)")
}
