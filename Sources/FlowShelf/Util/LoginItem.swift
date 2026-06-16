import ServiceManagement
import AppKit

/// Registers/unregisters FlowShelf as a launch-at-login item (macOS 13+).
/// Works for non-sandboxed apps installed in /Applications.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("FlowShelf: failed to update login item: \(error)")
        }
    }
}
