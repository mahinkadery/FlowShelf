import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

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

    /// `CGPreflightScreenCaptureAccess()` caches its answer for the whole life of
    /// the process — after the user grants access it keeps returning `false`
    /// until the app is fully relaunched (a well-known macOS quirk, confirmed by
    /// Apple DTS). That stale `false` is what makes users think the toggle didn't
    /// work and start removing/re-adding FlowShelf. So once a real capture
    /// actually succeeds we KNOW access is granted, and we latch that — the UI
    /// never reports "not granted" again for this run once anything has been
    /// captured.
    private static var captureConfirmed = false

    /// Called by the capture pipeline whenever a window capture actually works.
    static func noteScreenCaptureSucceeded() { captureConfirmed = true }

    static var hasScreenRecording: Bool {
        captureConfirmed || CGPreflightScreenCaptureAccess()
    }

    /// Actively confirm Screen Recording by attempting one real (tiny) capture,
    /// then latch the result. Cheap; no-ops once confirmed. Call at launch and
    /// whenever the app returns to the foreground, so the first read after the
    /// user grants access in System Settings isn't the stale cached `false`.
    static func warmScreenRecording() {
        guard !captureConfirmed else { return }
        if WindowService.shared.canCaptureNow() { captureConfirmed = true }
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: Input Monitoring (needed for global hardware-key HUDs)

    static var inputMonitoringStatus: IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    }

    static var hasInputMonitoring: Bool {
        inputMonitoringStatus == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Open the relevant System Settings pane.
    static func openSettings(_ pane: Pane) {
        if let url = URL(string: pane.urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    enum Pane {
        case accessibility, screenRecording, inputMonitoring, fullDiskAccess
        var urlString: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .screenRecording:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            case .inputMonitoring:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            case .fullDiskAccess:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            }
        }
    }
}
