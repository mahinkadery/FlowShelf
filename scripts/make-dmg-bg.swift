import AppKit

// Render a 2x (1200x800) DMG background: dark card, an arrow pointing from the
// app icon toward the Applications folder, and a hint line.
let W: CGFloat = 1200, H: CGFloat = 800
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// Background gradient (matches the app's dark theme).
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1),
    NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)])
grad?.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

// Arrow between the two icons (icons sit around y=205 from the top in a 400pt
// window → ~390 from bottom in this 800px-tall image).
let y: CGFloat = 470
NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = 10
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 520, y: y))
shaft.line(to: NSPoint(x: 690, y: y))
shaft.stroke()
let head = NSBezierPath()
head.lineWidth = 10
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 655, y: y + 26))
head.line(to: NSPoint(x: 692, y: y))
head.line(to: NSPoint(x: 655, y: y - 26))
head.stroke()

// Hint text near the bottom.
let title = "Drag FlowShelf onto Applications to install"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72)]
let size = title.size(withAttributes: attrs)
title.draw(at: NSPoint(x: (W - size.width) / 2, y: 150), withAttributes: attrs)

img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("make-dmg-bg: wrote \(out)")
}
