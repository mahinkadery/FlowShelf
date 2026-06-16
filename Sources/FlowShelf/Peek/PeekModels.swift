import AppKit
import CoreGraphics

/// A single capturable window belonging to some app.
struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleID: String?
    let pid: pid_t
    let frame: CGRect
    var thumbnail: NSImage?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && (lhs.thumbnail != nil) == (rhs.thumbnail != nil)
    }
}

/// All on-screen windows for one running app, with its icon. Used by the Peek grid.
struct AppWindows: Identifiable {
    let id: String
    let appName: String
    let bundleID: String?
    let pid: pid_t
    var icon: NSImage?
    var windows: [WindowInfo]
}
