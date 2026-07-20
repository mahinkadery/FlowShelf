import Foundation

/// Applies the four Notch preferences as one coherent runtime state. UI views
/// only mutate AppSettings; this coordinator owns which services are alive.
@MainActor
final class NotchRuntimeCoordinator {
    static let shared = NotchRuntimeCoordinator()

    private init() {}

    func apply() {
        let settings = AppSettings.shared

        guard settings.notchEnabled else {
            NotchController.shared.stop()
            MediaManager.shared.stop()
            AudioSpectrum.shared.setActive(false)
            return
        }

        NotchController.shared.start()
        NotchController.shared.setHUDEnabled(settings.notchHUDEnabled)

        if settings.notchMediaEnabled {
            MediaManager.shared.start()
            let now = MediaManager.shared.now
            AudioSpectrum.shared.setActive(
                settings.audioReactiveBars && now.hasMedia && now.isPlaying
            )
        } else {
            MediaManager.shared.stop()
            AudioSpectrum.shared.setActive(false)
        }
    }
}
