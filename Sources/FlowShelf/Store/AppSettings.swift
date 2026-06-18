import Foundation
import Combine
import CoreGraphics

/// Dock-preview thumbnail size options.
enum DockPreviewSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var thumb: CGSize {
        switch self {
        case .small:  return CGSize(width: 230, height: 144)
        case .medium: return CGSize(width: 300, height: 188)
        case .large:  return CGSize(width: 380, height: 238)
        }
    }
    /// Resolution to capture at, so larger tiles stay crisp.
    var captureDimension: CGFloat {
        switch self {
        case .small:  return 520
        case .medium: return 660
        case .large:  return 820
        }
    }
}

/// Visual style for the Option+Tab window switcher.
enum AltTabLayout: String, CaseIterable, Identifiable {
    case thumbnails, list
    var id: String { rawValue }
    var label: String { self == .thumbnails ? "Thumbnails" : "List" }
}

/// How long captured clipboard/shelf items live before auto-clearing.
enum ClipboardRetention: String, CaseIterable, Identifiable {
    case day, forever
    var id: String { rawValue }
    var label: String { self == .day ? "24 hours" : "Permanent" }
    var isForever: Bool { self == .forever }
}

/// User-facing preferences + the privacy controls for clipboard capture.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled") }
    }
    /// 24h auto-clear (default) or keep everything permanently.
    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: "clipboardRetention") }
    }
    /// "Private mode" — pauses clipboard capture entirely.
    @Published var privateMode: Bool {
        didSet { defaults.set(privateMode, forKey: "privateMode") }
    }
    /// Bundle IDs whose copies are never recorded (e.g. password managers).
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    /// Hover-a-Dock-icon live window previews (needs Accessibility + Screen Recording).
    @Published var dockPreviewsEnabled: Bool {
        didSet { defaults.set(dockPreviewsEnabled, forKey: "dockPreviewsEnabled") }
    }
    /// Shake the mouse to summon the floating shelf at the cursor.
    @Published var shakeToSummon: Bool {
        didSet { defaults.set(shakeToSummon, forKey: "shakeToSummon") }
    }
    /// Delay before a Dock-hover preview appears (seconds).
    @Published var dockPreviewHoverDelay: Double {
        didSet { defaults.set(dockPreviewHoverDelay, forKey: "dockPreviewHoverDelay") }
    }
    /// Dock-preview thumbnail size.
    @Published var dockPreviewSize: DockPreviewSize {
        didSet { defaults.set(dockPreviewSize.rawValue, forKey: "dockPreviewSize") }
    }
    /// Option+Tab window switcher.
    @Published var altTabEnabled: Bool {
        didSet { defaults.set(altTabEnabled, forKey: "altTabEnabled") }
    }
    @Published var altTabLayout: AltTabLayout {
        didSet { defaults.set(altTabLayout.rawValue, forKey: "altTabLayout") }
    }
    /// Magnet-style window snapping via ⌃⌥ + keys (needs Accessibility).
    @Published var windowSnapEnabled: Bool {
        didSet { defaults.set(windowSnapEnabled, forKey: "windowSnapEnabled") }
    }
    /// Dynamic-Island-style shelf living in the notch / top-center pill.
    @Published var notchEnabled: Bool {
        didSet { defaults.set(notchEnabled, forKey: "notchEnabled") }
    }
    /// Open the annotation editor after a region screenshot.
    @Published var annotateAfterScreenshot: Bool {
        didSet { defaults.set(annotateAfterScreenshot, forKey: "annotateAfterScreenshot") }
    }
    /// Show on-device AI actions (summarize / clean / smart title). Only has any
    /// effect on Apple-Intelligence-capable Macs.
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: "aiEnabled") }
    }
    /// Auto-generate a title for new text items via AI. Off by default — it runs
    /// the model on capture, so it's opt-in for people watching battery/RAM.
    @Published var aiAutoTitle: Bool {
        didSet { defaults.set(aiAutoTitle, forKey: "aiAutoTitle") }
    }

    /// One-shot: skip recording the very next copy.
    var ignoreNextCopy = false

    private init() {
        clipboardEnabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        clipboardRetention = ClipboardRetention(rawValue: defaults.string(forKey: "clipboardRetention") ?? "") ?? .day
        privateMode = defaults.bool(forKey: "privateMode")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        dockPreviewsEnabled = defaults.bool(forKey: "dockPreviewsEnabled")
        shakeToSummon = defaults.bool(forKey: "shakeToSummon")
        dockPreviewHoverDelay = defaults.object(forKey: "dockPreviewHoverDelay") as? Double ?? 0.28
        dockPreviewSize = DockPreviewSize(rawValue: defaults.string(forKey: "dockPreviewSize") ?? "")
            ?? .medium
        altTabEnabled = defaults.bool(forKey: "altTabEnabled")
        altTabLayout = AltTabLayout(rawValue: defaults.string(forKey: "altTabLayout") ?? "") ?? .thumbnails
        windowSnapEnabled = defaults.bool(forKey: "windowSnapEnabled")
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        annotateAfterScreenshot = defaults.bool(forKey: "annotateAfterScreenshot")
        aiEnabled = defaults.object(forKey: "aiEnabled") as? Bool ?? true
        aiAutoTitle = defaults.bool(forKey: "aiAutoTitle")
        // Default-exclude common password managers.
        excludedBundleIDs = defaults.object(forKey: "excludedBundleIDs") as? [String] ?? [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "com.apple.keychainaccess"
        ]
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedBundleIDs.contains(id)
    }
}
