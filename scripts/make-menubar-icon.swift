import AppKit

// Turn a black-on-white glyph PNG into a macOS *template* image: the dark shape
// becomes opaque black, light pixels become transparent, and the result is
// cropped to the glyph's bounding box. Set isTemplate=true on the NSImage and
// macOS tints it for the menu bar automatically.

let inPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/MenuBarSource.png"
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/MenuBarIcon.png"

guard let src = NSImage(contentsOfFile: inPath),
      let srcTiff = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff) else { print("bad source"); exit(1) }

let W = srcRep.pixelsWide, H = srcRep.pixelsHigh

// Draw into a known RGBA8 context so pixel reads are predictable.
let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: W * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
srcRep.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()

guard let inBuf = canvas.bitmapData else { exit(1) }

let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: W * 4, bitsPerPixel: 32)!
let outBuf = out.bitmapData!

var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H {
    for x in 0..<W {
        let i = (y * W + x) * 4
        let r = Double(inBuf[i]), g = Double(inBuf[i+1]), b = Double(inBuf[i+2])
        let a = Double(inBuf[i+3]) / 255.0
        let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        // Dark shape → opaque; light/background → transparent.
        let alpha = max(0, min(1, (1.0 - lum))) * a
        let av = UInt8(alpha * 255)
        outBuf[i] = 0; outBuf[i+1] = 0; outBuf[i+2] = 0; outBuf[i+3] = av  // black + alpha
        if alpha > 0.35 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
    }
}

// Crop to the glyph bounding box (top-left origin, matches the pixel buffer).
let pad = 6
let cx = max(0, minX - pad), cy = max(0, minY - pad)
let cw = min(W - cx, maxX - minX + 2 * pad), ch = min(H - cy, maxY - minY + 2 * pad)

guard let cg = out.cgImage,
      let cropped = cg.cropping(to: CGRect(x: cx, y: cy, width: cw, height: ch)) else { exit(1) }
let rep2 = NSBitmapImageRep(cgImage: cropped)
if let png = rep2.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: outPath))
    print("make-menubar-icon: wrote \(outPath) (\(cw)x\(ch) template)")
}
