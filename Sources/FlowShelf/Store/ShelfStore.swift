import AppKit
import Combine
import UniformTypeIdentifiers

/// The single source of truth for everything on the Shelf.
/// Owns persistence, the 24-hour expiry sweep, and on-disk image/thumbnail files.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ShelfItem] = []

    private let baseDir: URL
    private let filesDir: URL
    private let dbURL: URL
    private var sweepTimer: Timer?

    private let maxImageDimension: CGFloat = 2200      // cap stored screenshots
    private let thumbDimension: CGFloat = 220

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = appSupport.appendingPathComponent("FlowShelf", isDirectory: true)
        filesDir = baseDir.appendingPathComponent("files", isDirectory: true)
        dbURL = baseDir.appendingPathComponent("shelf.json")

        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        load()
        sweepExpired()
        startSweepTimer()
    }

    // MARK: - Public API

    /// Items currently visible: not expired, newest first, pinned floated to top.
    var visibleItems: [ShelfItem] {
        items
            .filter { !$0.isExpired }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned && !b.pinned }
                return a.createdAt > b.createdAt
            }
    }

    func add(_ item: ShelfItem) {
        // De-dupe consecutive identical text/link copies.
        if let newest = items.first,
           newest.kind == item.kind,
           newest.text != nil,
           newest.text == item.text {
            return
        }
        items.insert(item, at: 0)
        persist()
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        // Re-anchor expiry from now when unpinning so it lives a fresh 24h.
        if !items[idx].pinned {
            items[idx].expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        }
        persist()
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        deleteFiles(for: items[idx])
        items.remove(at: idx)
        persist()
    }

    func clearAll(includingPinned: Bool = false) {
        let survivors = includingPinned ? [] : items.filter { $0.pinned }
        for item in items where !survivors.contains(where: { $0.id == item.id }) {
            deleteFiles(for: item)
        }
        items = survivors
        persist()
    }

    func item(_ id: UUID) -> ShelfItem? { items.first { $0.id == id } }

    func fileURL(forRel rel: String) -> URL { filesDir.appendingPathComponent(rel) }

    func imageURL(for item: ShelfItem) -> URL? {
        guard let rel = item.imageRelPath else { return nil }
        return fileURL(forRel: rel)
    }

    func thumbnail(for item: ShelfItem) -> NSImage? {
        if let rel = item.thumbRelPath,
           let img = NSImage(contentsOf: fileURL(forRel: rel)) {
            return img
        }
        if let url = imageURL(for: item) { return NSImage(contentsOf: url) }
        return nil
    }

    // MARK: - Convenience constructors

    /// Persist an image (NSImage) to disk and return relative paths.
    /// Returns (imageRelPath, thumbRelPath).
    func storeImage(_ image: NSImage, prefix: String) -> (String, String?)? {
        let id = UUID().uuidString
        let imageRel = "\(prefix)-\(id).png"
        let thumbRel = "\(prefix)-\(id)-thumb.png"

        let capped = image.resized(maxDimension: maxImageDimension)
        guard let pngData = capped.pngData() else { return nil }
        do {
            try pngData.write(to: fileURL(forRel: imageRel))
        } catch {
            return nil
        }

        var savedThumb: String? = nil
        if let thumb = image.resized(maxDimension: thumbDimension).pngData() {
            if (try? thumb.write(to: fileURL(forRel: thumbRel))) != nil {
                savedThumb = thumbRel
            }
        }
        return (imageRel, savedThumb)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dbURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ShelfItem].self, from: data) {
            items = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: dbURL, options: .atomic)
        }
    }

    // MARK: - Expiry

    private func startSweepTimer() {
        // Sweep every 5 minutes; cheap and keeps the shelf honest.
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepExpired() }
        }
    }

    func sweepExpired() {
        let expired = items.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        for item in expired { deleteFiles(for: item) }
        items.removeAll { $0.isExpired }
        persist()
    }

    private func deleteFiles(for item: ShelfItem) {
        for rel in [item.imageRelPath, item.thumbRelPath].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: fileURL(forRel: rel))
        }
    }
}
