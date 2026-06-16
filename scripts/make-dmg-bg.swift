import AppKit

// DMG background at the EXACT window point size (1x, 72 DPI) so Finder shows it
// without scaling/distortion and the icons line up. Standard 660x420 window.
// The two draggable icons (FlowShelf.app + Applications) are placed by Finder, so
// we leave their spots empty and only draw chrome around them.

let W: CGFloat = 660, H: CGFloat = 420
let amber = NSColor(srgbRed: 0.97, green: 0.66, blue: 0.15, alpha: 1)
func fromTop(_ t: CGFloat) -> CGFloat { H - t }

// Icon spots (must match build-dmg.sh icon positions).
let appX: CGFloat = 190, dirX: CGFloat = 470, iconY: CGFloat = 200

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.jpg"

// Draw into an EXPLICIT 660x420 px bitmap at 72 DPI (NSImage.lockFocus would
// render at 2x/144 DPI on a retina Mac, which Finder then distorts).
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // 72 DPI (points == pixels)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

if let base = NSImage(contentsOfFile: "Resources/dmg-bg-base.png") {
    base.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
} else {
    NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
}

func centeredText(_ s: String, font: NSFont, color: NSColor, top: CGFloat) {
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let sz = s.size(withAttributes: a)
    s.draw(at: NSPoint(x: (W - sz.width) / 2, y: fromTop(top) - sz.height), withAttributes: a)
}

// Title: logo + "Flow"(white)+"Shelf"(amber), centered near the top.
let titleFont = NSFont.systemFont(ofSize: 34, weight: .bold)
let flowW = "Flow".size(withAttributes: [.font: titleFont]).width
let shelfW = "Shelf".size(withAttributes: [.font: titleFont]).width
let titleH = "Flow".size(withAttributes: [.font: titleFont]).height
let logoS: CGFloat = 46, gap: CGFloat = 12
var x = (W - (logoS + gap + flowW + shelfW)) / 2
let titleTop: CGFloat = 40
if let logo = NSImage(contentsOfFile: "Resources/AppIcon.png") {
    logo.draw(in: NSRect(x: x, y: fromTop(titleTop) - logoS + 4, width: logoS, height: logoS))
}
x += logoS + gap
"Flow".draw(at: NSPoint(x: x, y: fromTop(titleTop) - titleH), withAttributes: [.font: titleFont, .foregroundColor: NSColor.white])
"Shelf".draw(at: NSPoint(x: x + flowW, y: fromTop(titleTop) - titleH), withAttributes: [.font: titleFont, .foregroundColor: amber])

// Tagline.
centeredText("Organize everything. Find anything.",
             font: .systemFont(ofSize: 16, weight: .regular),
             color: NSColor(calibratedWhite: 0.72, alpha: 1), top: 96)

// Arrow centered between the two icon spots, at the icon row.
let ay = fromTop(iconY)
let ax = (appX + dirX) / 2
NSColor(calibratedWhite: 0.82, alpha: 0.9).setStroke()
let shaft = NSBezierPath(); shaft.lineWidth = 5; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: ax - 26, y: ay)); shaft.line(to: NSPoint(x: ax + 26, y: ay)); shaft.stroke()
let head = NSBezierPath(); head.lineWidth = 5; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: ax + 12, y: ay + 14)); head.line(to: NSPoint(x: ax + 28, y: ay)); head.line(to: NSPoint(x: ax + 12, y: ay - 14)); head.stroke()

// Install line.
centeredText("Drag FlowShelf onto the Applications folder to install",
             font: .systemFont(ofSize: 15, weight: .medium),
             color: NSColor(calibratedWhite: 0.9, alpha: 1), top: 320)

// First-launch instructions (Gatekeeper).
centeredText("First time opening? Apple shows a security prompt — it’s safe.",
             font: .systemFont(ofSize: 12.5, weight: .regular),
             color: NSColor(calibratedWhite: 0.62, alpha: 1), top: 352)
centeredText("System Settings ▸ Privacy & Security ▸ scroll down ▸ “Open Anyway”",
             font: .systemFont(ofSize: 12.5, weight: .semibold),
             color: amber.withAlphaComponent(0.92), top: 374)

NSGraphicsContext.restoreGraphicsState()
if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
    try? jpg.write(to: URL(fileURLWithPath: out))
    print("make-dmg-bg: wrote \(out) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}
