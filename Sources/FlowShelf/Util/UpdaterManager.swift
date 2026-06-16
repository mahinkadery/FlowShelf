import AppKit
import Sparkle

/// Wraps Sparkle so FlowShelf can check for, download, and install updates from
/// the appcast feed (SUFeedURL in Info.plist). Auto-checks daily; users can also
/// check manually from Settings.
@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Touch this once at launch so the updater starts its background schedule.
    func start() {}

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
