import AppKit

/// Relaunches FlowShelf. Needed because macOS only applies a freshly-granted
/// Accessibility trust to the *next* launch of a process — `AXIsProcessTrusted()`
/// stays false for the current run.
@MainActor
enum AppRelaunch {
    static func relaunch(at url: URL = Bundle.main.bundleURL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { application, error in
            DispatchQueue.main.async {
                guard application != nil, error == nil else {
                    let alert = NSAlert()
                    alert.messageText = "FlowShelf couldn’t reopen"
                    alert.informativeText = "Your current session is still running. Try opening FlowShelf again from Applications."
                    alert.runModal()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
