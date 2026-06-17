import AppKit
import ApplicationServices
import CoreGraphics

/// Centralized permission checks + prompts. FlowShelf asks for a permission only
/// when the user first uses the feature that needs it (per the design).
@MainActor
enum Permissions {

    // MARK: Accessibility (needed to read the Dock + raise windows)

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts (system dialog) if not yet trusted. Returns current state.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Screen Recording (needed for window thumbnails)

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Open the relevant System Settings pane.
    static func openSettings(_ pane: Pane) {
        if let url = URL(string: pane.urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    enum Pane {
        case accessibility, screenRecording, fullDiskAccess
        var urlString: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .screenRecording:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            case .fullDiskAccess:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            }
        }
    }
}
