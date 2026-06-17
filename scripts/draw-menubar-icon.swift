import AppKit

// Draw a clean, simplified FlowShelf glyph for the menu bar: a tray/basket with a
// card poking out the top (matches the app icon's idea, no busy interior detail).
// Output is a black template on transparency → macOS tints it for the menu bar.

let S = 440
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: S * 4, bitsPerPixel: 32)!
let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = g
g.cgContext.translateBy(x: 0, y: CGFloat(S)); g.cgContext.scaleBy(x: 1, y: -1)  // top-left origin
g.cgContext.setAllowsAntialiasing(true)
NSColor.black.setFill()
NSColor.black.setStroke()

// Card poking out the top (narrower than the basket so the rim shows on each side).
let card = NSBezierPath(roundedRect: NSRect(x: 138, y: 44, width: 164, height: 132),
                        xRadius: 22, yRadius: 22)
card.fill()

// Basket / tray: an open container (thick stroked outline so it reads as a shelf,
// not a solid blob). Trapezoid, wider at the top rim.
let basket = NSBezierPath()
basket.lineWidth = 34
basket.lineJoinStyle = .round
basket.lineCapStyle = .round
basket.move(to: NSPoint(x: 70, y: 168))     // top-left rim
basket.line(to: NSPoint(x: 92, y: 360))     // down-left
basket.curve(to: NSPoint(x: 348, y: 360),   // across the rounded bottom
             controlPoint1: NSPoint(x: 150, y: 392), controlPoint2: NSPoint(x: 290, y: 392))
basket.line(to: NSPoint(x: 370, y: 168))    // up-right
basket.stroke()

// Top rim of the basket (a bar across the opening).
let rim = NSBezierPath()
rim.lineWidth = 34
rim.lineCapStyle = .round
rim.move(to: NSPoint(x: 70, y: 168))
rim.line(to: NSPoint(x: 370, y: 168))
rim.stroke()

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/MenuBarIcon.png"
if let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("draw-menubar-icon: wrote \(out)")
}
