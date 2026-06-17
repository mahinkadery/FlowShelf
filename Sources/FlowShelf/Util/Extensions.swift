import AppKit
import SwiftUI

extension NSImage {
    /// The bundled FlowShelf shelf glyph as a menu-bar template image (auto-tinted
    /// by macOS), sized to `height`. Falls back to nil if the asset is missing.
    static func menuBarGlyph(height: CGFloat) -> NSImage? {
        guard let img = Bundle.main.loadImage("MenuBarIcon") else { return nil }
        img.isTemplate = true
        let ratio = img.size.height > 0 ? img.size.width / img.size.height : 1
        img.size = NSSize(width: height * ratio, height: height)
        return img
    }
}

/// FlowShelf's shelf glyph for in-app headers (template, tintable).
struct FlowShelfGlyph: View {
    var size: CGFloat = 16
    var color: Color = .accentColor
    var body: some View {
        Group {
            if let img = Bundle.main.loadImage("MenuBarIcon") {
                Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: "tray.full.fill").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(color)
    }
}

extension NSImage {
    /// PNG data for the image at its current representation.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Downscale so the longest edge is at most `maxDimension`. Never upscales.
    func resized(maxDimension: CGFloat) -> NSImage {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return self }
        let longest = max(w, h)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = NSSize(width: floor(w * scale), height: floor(h * scale))
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        out.unlockFocus()
        return out
    }
}

extension Bundle {
    /// Load a loose image resource (e.g. bundled PNG) from the app bundle.
    func loadImage(_ name: String, ext: String = "png") -> NSImage? {
        guard let url = url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}

extension String {
    /// Heuristic: does this text look like a single URL?
    var looksLikeURL: Bool {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), t.count < 2048 else { return false }
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    /// First non-empty line, trimmed and clipped — used for row titles.
    func firstLine(max: Int = 80) -> String {
        let line = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }
}

extension Date {
    /// "2:42 PM" style short time, used in row subtitles.
    var shortTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: self)
    }
}
