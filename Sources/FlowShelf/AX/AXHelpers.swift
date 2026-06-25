import AppKit
import ApplicationServices

// Private API used by DockDoor/AltTab etc. to bridge an AX window element to its
// CoreGraphics window id. Declared here so we can match AX windows to SCWindows.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin helpers over the Accessibility API for reading window lists, frames, and
/// raising/activating windows by their CoreGraphics window id.
enum AX {

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return err == .success ? value : nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func windows(ofApp pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        return (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    static func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(element, &wid) == .success ? wid : nil
    }

    static func title(of element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute as String) as? String
    }

    static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute as String) as? String
    }

    static func subrole(of element: AXUIElement) -> String? {
        attribute(element, kAXSubroleAttribute as String) as? String
    }

    static func url(of element: AXUIElement) -> URL? {
        (attribute(element, kAXURLAttribute as String) as? NSURL)?.absoluteURL
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXMinimizedAttribute as String) as? Bool) ?? false
    }

    /// The Dock's icon list element (the AXList holding all dock items).
    static func dockList(dockPID: pid_t) -> AXUIElement? {
        let dock = AXUIElementCreateApplication(dockPID)
        return children(dock).first { role(of: $0) == (kAXListRole as String) }
    }

    /// The dock item the user is currently hovering, if any (macOS marks it as
    /// the list's "selected child").
    static func selectedDockItem(dockPID: pid_t) -> AXUIElement? {
        guard let list = dockList(dockPID: dockPID) else { return nil }
        let selected = attribute(list, kAXSelectedChildrenAttribute as String) as? [AXUIElement]
        return selected?.first
    }

    /// Screen frame (top-left origin, like CoreGraphics) of an AX element.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let posVal = attribute(element, kAXPositionAttribute as String),
              let sizeVal = attribute(element, kAXSizeAttribute as String),
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Raise a specific window (by CG window id) of an app and bring it forward.
    @MainActor
    static func raiseWindow(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        if let axWindows = attribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement] {
            for axWindow in axWindows where cgWindowID(of: axWindow) == windowID {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                break
            }
        }
        // Bring the app forward via Accessibility — this works even when FlowShelf
        // itself is in the background, whereas NSRunningApplication.activate() is
        // blocked for non-frontmost apps (that's why only the first switch worked).
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        activate(pid: pid)
    }

    @MainActor
    static func activate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    @MainActor
    static func closeWindow(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        guard let axWindows = attribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else { return }
        for axWindow in axWindows where cgWindowID(of: axWindow) == windowID {
            if let closeButton = attribute(axWindow, kAXCloseButtonAttribute as String),
               CFGetTypeID(closeButton) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
            }
            break
        }
    }

    // MARK: - Window move/resize (for snapping/tiling)

    /// The focused window of the frontmost app (falls back to its first window).
    @MainActor
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let win = attribute(axApp, kAXFocusedWindowAttribute as String),
           CFGetTypeID(win) == AXUIElementGetTypeID() {
            return (win as! AXUIElement)
        }
        return (attribute(axApp, kAXWindowsAttribute as String) as? [AXUIElement])?.first
    }

    /// Move + resize a window. Frame is in AX coords (top-left origin, y-down).
    /// Position is set twice (apps sometimes clamp size first), so the final
    /// placement lands where we asked.
    static func setFrame(_ element: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }
    }

    /// Convert between AX/Quartz coords (top-left origin, y grows down) and Cocoa
    /// coords (bottom-left origin, y grows up). The transform is its own inverse.
    static func flipY(_ r: CGRect) -> CGRect {
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
        return CGRect(x: r.origin.x, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    @MainActor
    static func minimizeWindow(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        guard let axWindows = attribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else { return }
        for axWindow in axWindows where cgWindowID(of: axWindow) == windowID {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            break
        }
    }
}
