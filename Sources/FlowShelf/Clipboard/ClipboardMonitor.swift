import AppKit
import Combine
import UniformTypeIdentifiers

/// Watches `NSPasteboard.general` and turns each new copy into a Shelf item.
/// Lightweight: polls `changeCount` rather than hooking the pasteboard.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let store = ShelfStore.shared
    private let settings = AppSettings.shared
    @Published private(set) var accessWarning: String?
    private var captureGeneration = UUID()
    private var settingsSubscription: AnyCancellable?

    private init() {}

    func start() {
        guard timer == nil else { return }
        captureGeneration = UUID()
        settingsSubscription = settings.$clipboardEnabled.combineLatest(settings.$privateMode)
            .sink { [weak self] _ in self?.captureGeneration = UUID() }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        captureGeneration = UUID()
        settingsSubscription = nil
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        var warning: String?
        if #available(macOS 15.4, *) {
            switch pb.accessBehavior {
            case .alwaysDeny:
                warning = "Clipboard access is blocked by macOS. Allow FlowShelf in System Settings to resume automatic capture."
            case .ask:
                warning = "Automatic capture is paused to avoid repeated permission prompts. Set FlowShelf’s clipboard access to Always Allow in System Settings."
            default:
                break
            }
        }
        if warning != accessWarning { accessWarning = warning }
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard settings.clipboardEnabled, !settings.privateMode else { return }

        if settings.ignoreNextCopy {
            settings.ignoreNextCopy = false
            return
        }
        guard warning == nil else { return }

        if ClipboardPrivacyRules.shouldIgnore(pb, customTypes: settings.ignoredClipboardTypes) {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if settings.isExcluded(bundleID: frontApp?.bundleIdentifier) { return }
        let appName = frontApp?.localizedName

        capture(from: pb, sourceApp: appName, sourceBundleID: frontApp?.bundleIdentifier)
    }

    private func capture(from pb: NSPasteboard, sourceApp: String?, sourceBundleID: String?) {
        // 1. File URLs (dragged/copied files) — store as references, don't duplicate.
        let urls = ClipboardPayload.fileURLs(in: pb)
        if !urls.isEmpty {
            for url in urls.reversed() {
                addFile(url: url, sourceApp: sourceApp)
            }
            return
        }

        // 2. Image data. Accept anything that's genuinely an image type — not
        //    just TIFF/PNG. Universal Clipboard photos from an iPhone often
        //    arrive as JPEG or HEIC only, and were being silently dropped.
        if let img = NSImage(pasteboard: pb), Self.hasImageData(pb) {
            let generation = captureGeneration
            store.storeImage(img, prefix: "clip", isStillValid: { [weak self] in
                guard let self else { return false }
                return self.captureGeneration == generation && self.timer != nil
                    && self.settings.clipboardEnabled && !self.settings.privateMode
                    && !self.settings.isExcluded(bundleID: sourceBundleID)
            }) { [weak self] result in
                guard let self, let (rel, thumb) = result else { return }
                store.add(ShelfItem(
                    kind: .image,
                    title: "Image",
                    preview: "Copied image",
                    sourceApp: sourceApp,
                    imageRelPath: rel,
                    thumbRelPath: thumb
                ))
            }
            return
        }

        // 3. Text / links.
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isLink = text.looksLikeURL
            store.add(ShelfItem(
                kind: isLink ? .link : .text,
                title: isLink ? (URL(string: text)?.host ?? "Link") : text.firstLine(),
                preview: text.firstLine(max: 140),
                text: text,
                richTextRTF: ClipboardPayload.boundedRTF(pb.data(forType: .rtf)),
                sourceApp: sourceApp
            ))
        }
    }

    /// True when the pasteboard carries real image bytes (TIFF, PNG, JPEG, HEIC,
    /// GIF…) — i.e. any type conforming to `public.image`. Guards against
    /// treating PDF or rich text that `NSImage` can *render* as a copied image.
    private static func hasImageData(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    private func addFile(url: URL, sourceApp: String?) {
        let bookmark = try? url.bookmarkData(options: .minimalBookmark)
        store.add(ShelfItem(
            kind: .file,
            title: url.lastPathComponent,
            preview: url.deletingLastPathComponent().path,
            sourceApp: sourceApp,
            fileBookmark: bookmark,
            filePath: url.path
        ))
    }
}
