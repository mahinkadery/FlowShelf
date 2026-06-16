import Foundation
import Combine

/// User-facing preferences + the privacy controls for clipboard capture.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled") }
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

    /// One-shot: skip recording the very next copy.
    var ignoreNextCopy = false

    private init() {
        clipboardEnabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        privateMode = defaults.bool(forKey: "privateMode")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        dockPreviewsEnabled = defaults.bool(forKey: "dockPreviewsEnabled")
        shakeToSummon = defaults.bool(forKey: "shakeToSummon")
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
