import AppKit

/// Relaunches FlowShelf. Needed because macOS only applies a freshly-granted
/// Accessibility trust to the *next* launch of a process — `AXIsProcessTrusted()`
/// stays false for the current run.
@MainActor
enum AppRelaunch {
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
