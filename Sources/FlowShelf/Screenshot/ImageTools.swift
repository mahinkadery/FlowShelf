import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Multi-image utilities: stitch screenshots into one canvas, and build a
/// before/after animated GIF. All local, no network.
enum ImageTools {

    static func pixelSize(_ image: NSImage) -> NSSize {
        if let rep = image.representations.first {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    /// Stack images into a single canvas (vertical by default), centred on `bg`.
    static func stack(_ images: [NSImage], vertical: Bool = true,
                      gap: CGFloat = 0, bg: NSColor = .white) -> NSImage? {
        let sizes = images.map { pixelSize($0) }
        guard !sizes.isEmpty else { return nil }
        let n = CGFloat(images.count)
        let w = vertical ? (sizes.map { $0.width }.max() ?? 0)
                         : sizes.map { $0.width }.reduce(0, +) + gap * (n - 1)
        let h = vertical ? sizes.map { $0.height }.reduce(0, +) + gap * (n - 1)
                         : (sizes.map { $0.height }.max() ?? 0)
        guard w > 0, h > 0 else { return nil }

        let out = NSImage(size: NSSize(width: w, height: h))
        out.lockFocus()
        bg.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        // NSImage origin is bottom-left; stack top→bottom for vertical.
        var cursor: CGFloat = vertical ? h : 0
        for (img, size) in zip(images, sizes) {
            if vertical {
                cursor -= size.height
                img.draw(in: NSRect(x: (w - size.width) / 2, y: cursor, width: size.width, height: size.height))
                cursor -= gap
            } else {
                img.draw(in: NSRect(x: cursor, y: (h - size.height) / 2, width: size.width, height: size.height))
                cursor += size.width + gap
            }
        }
        out.unlockFocus()
        return out
    }

    /// Pad every frame to a common size (centred on white) so a GIF lines up.
    static func normalize(_ images: [NSImage]) -> [NSImage] {
        let sizes = images.map { pixelSize($0) }
        let w = sizes.map { $0.width }.max() ?? 0
        let h = sizes.map { $0.height }.max() ?? 0
        guard w > 0, h > 0 else { return images }
        return images.map { img in
            let s = pixelSize(img)
            let out = NSImage(size: NSSize(width: w, height: h))
            out.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
            img.draw(in: NSRect(x: (w - s.width) / 2, y: (h - s.height) / 2, width: s.width, height: s.height))
            out.unlockFocus()
            return out
        }
    }

    /// Build an animated GIF that loops forever, `seconds` per frame.
    static func makeGIF(frames: [NSImage], seconds: Double = 0.8) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }

        let fileProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFDelayTime as String: seconds]]
        for img in frames {
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }
        return CGImageDestinationFinalize(dest) ? (data as Data) : nil
    }
}
