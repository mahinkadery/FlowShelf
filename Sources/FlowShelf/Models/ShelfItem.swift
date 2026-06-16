import Foundation

/// The kind of thing living on the Shelf. Everything temporary becomes one of these.
enum ItemKind: String, Codable, CaseIterable {
    case text
    case link
    case image
    case file
    case screenshot
    case ocr
    case cleanReport      // reserved for the Cleaner (v3)

    var symbol: String {
        switch self {
        case .text:        return "text.alignleft"
        case .link:        return "link"
        case .image:       return "photo"
        case .file:        return "doc"
        case .screenshot:  return "camera.viewfinder"
        case .ocr:         return "text.viewfinder"
        case .cleanReport: return "trash"
        }
    }

    var label: String {
        switch self {
        case .text:        return "Text"
        case .link:        return "Link"
        case .image:       return "Image"
        case .file:        return "File"
        case .screenshot:  return "Screenshot"
        case .ocr:         return "OCR"
        case .cleanReport: return "Cleanup"
        }
    }
}

/// A single Shelf item. This is the one currency the whole app trades in:
/// clipboard copies, screenshots, OCR text, and dragged files are all `ShelfItem`s.
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ItemKind
    var title: String
    /// Short preview text shown in the row (plain text, link, OCR result, filename…).
    var preview: String
    /// Full text payload for text/link/ocr items.
    var text: String?
    /// App the item came from, if known.
    var sourceApp: String?
    var createdAt: Date
    var expiresAt: Date
    var pinned: Bool
    /// Relative path (inside the store's files dir) to a copied image/screenshot.
    var imageRelPath: String?
    /// Relative path to a generated thumbnail.
    var thumbRelPath: String?
    /// Security-scoped bookmark for file references (not duplicated).
    var fileBookmark: Data?
    /// Original on-disk path for file items, for display + drag-out.
    var filePath: String?

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String,
        preview: String,
        text: String? = nil,
        sourceApp: String? = nil,
        createdAt: Date = Date(),
        ttl: TimeInterval = 24 * 60 * 60,
        pinned: Bool = false,
        imageRelPath: String? = nil,
        thumbRelPath: String? = nil,
        fileBookmark: Data? = nil,
        filePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.text = text
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttl)
        self.pinned = pinned
        self.imageRelPath = imageRelPath
        self.thumbRelPath = thumbRelPath
        self.fileBookmark = fileBookmark
        self.filePath = filePath
    }

    /// Pinned items never expire; everything else clears after its TTL.
    var isExpired: Bool {
        guard !pinned else { return false }
        return Date() >= expiresAt
    }

    var hasImage: Bool { imageRelPath != nil }

    /// Seconds until auto-delete (negative once past).
    var secondsRemaining: TimeInterval { expiresAt.timeIntervalSinceNow }

    /// Compact "time left" label for the UI, e.g. "23h left", "12m left".
    var expiryLabel: String {
        if pinned { return "Pinned" }
        let s = secondsRemaining
        if s <= 0 { return "expiring…" }
        if s < 3600 { return "\(Int(ceil(s / 60)))m left" }
        if s < 86_400 { return "\(Int(s / 3600))h left" }
        return "\(Int(s / 86_400))d left"
    }

    /// True when the item is within the last hour of its life (for emphasis).
    var expiringSoon: Bool { !pinned && secondsRemaining < 3600 }
}
