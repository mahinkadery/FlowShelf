import AppKit

/// Enumerates an app's windows via the Accessibility API (so the window *list*
/// works with only Accessibility granted) and captures thumbnails via the private
/// CGS window-capture API (DockDoor's approach), which additionally needs Screen
/// Recording.
///
/// Key lesson from DockDoor: never use enumeration to learn *what* windows exist
/// through a capture API — use Accessibility for the list, and capture each window
/// by its CGWindowID directly.
@MainActor
final class WindowService {
    static let shared = WindowService()
    private init() {}

    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    // MARK: - Enumeration (Accessibility only)

    /// Standard windows for a pid, front first, without thumbnails.
    func axWindows(pid: pid_t, appName: String, bundleID: String?) -> [WindowInfo] {
        var result: [WindowInfo] = []
        for axWindow in AX.windows(ofApp: pid) {
            let subrole = AX.subrole(of: axWindow)
            guard subrole == (kAXStandardWindowSubrole as String) || subrole == nil else { continue }
            guard let wid = AX.cgWindowID(of: axWindow) else { continue }
            let frame = AX.frame(of: axWindow) ?? .zero
            guard frame.width > 60, frame.height > 60 else { continue }

            let title = AX.title(of: axWindow) ?? appName
            result.append(WindowInfo(
                id: wid,
                title: title.isEmpty ? appName : title,
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                frame: frame,
                thumbnail: nil))
        }
        return result
    }

    // MARK: - With thumbnails

    func loadWindows(pid: pid_t, appName: String, bundleID: String?,
                     thumbnails: Bool) async -> [WindowInfo] {
        var windows = axWindows(pid: pid, appName: appName, bundleID: bundleID)
        guard thumbnails else { return windows }
        // Always attempt the capture — never gate on CGPreflightScreenCaptureAccess,
        // which lies (stays false after the user grants the permission). The
        // capture itself returns nil if genuinely denied.
        let dim = AppSettings.shared.dockPreviewSize.captureDimension
        for i in windows.indices {
            windows[i].thumbnail = captureWindow(windowID: windows[i].id, maxDimension: dim)
        }
        return windows
    }

    /// All regular apps that currently have windows — for the Peek grid.
    func allAppWindows(thumbnails: Bool) async -> [AppWindows] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }
        let canCapture = thumbnails   // attempt regardless; capture is the ground truth
        var groups: [AppWindows] = []

        for app in apps {
            let name = app.localizedName ?? "App"
            var windows = axWindows(pid: app.processIdentifier, appName: name,
                                    bundleID: app.bundleIdentifier)
            guard !windows.isEmpty else { continue }
            if canCapture {
                for i in windows.indices {
                    windows[i].thumbnail = captureWindow(windowID: windows[i].id, maxDimension: 420)
                }
            }
            groups.append(AppWindows(
                id: app.bundleIdentifier ?? name,
                appName: name,
                bundleID: app.bundleIdentifier,
                pid: app.processIdentifier,
                icon: app.icon,
                windows: windows))
        }
        return groups.sorted { $0.appName.lowercased() < $1.appName.lowercased() }
    }

    // MARK: - Ground-truth permission check

    /// Can we actually capture a window *right now*? Tries to grab any on-screen
    /// window (found via CGWindowList — no Accessibility needed). Far more reliable
    /// than `CGPreflightScreenCaptureAccess`, which keeps returning false even
    /// after the user grants the permission.
    func canCaptureNow() -> Bool {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let num = w[kCGWindowNumber as String] as? UInt32,
                  let owner = w[kCGWindowOwnerName as String] as? String,
                  owner != "FlowShelf" else { continue }
            if captureWindow(windowID: num, maxDimension: 64) != nil { return true }
        }
        return false
    }

    // MARK: - Capture (private CGS, by window id)

    /// Capture a single window by its CGWindowID. Works for non-frontmost and
    /// occluded windows. Returns nil without Screen Recording permission.
    func captureWindow(windowID: CGWindowID, maxDimension: CGFloat) -> NSImage? {
        var wid = UInt32(windowID)
        let options: CGSWindowCaptureOptions = [.ignoreGlobalClipShape, .bestResolution]
        guard let array = CGSHWCaptureWindowList(CGSMainConnectionID(), &wid, 1, options) as? [CGImage],
              let cg = array.first else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return image.resized(maxDimension: maxDimension)
    }
}
