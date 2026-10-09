import AppKit
import ApplicationServices

// Private SkyLight/CGS window-capture API — the same one DockDoor & AltTab use.
// Captures a window by its CGWindowID even when it's not frontmost or is occluded
// (ScreenCaptureKit's on-screen filtering + windowID matching is less reliable).
// Still requires Screen Recording permission.
typealias CGSConnectionID = UInt32
typealias CGSWindowCount = UInt32

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

final class PrivateWindowSymbols {
    typealias Orientation = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void
    typealias Connection = @convention(c) () -> UInt32
    typealias Capture = @convention(c) (UInt32, UnsafePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
    typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    static let shared = PrivateWindowSymbols()
    private let orientation: Orientation?
    private let connection: Connection?
    private let capture: Capture?
    private let windowID: WindowID?

    init(resolve: (String) -> UnsafeMutableRawPointer? = { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) }) {
        orientation = resolve("CoreDockGetOrientationAndPinning").map { unsafeBitCast($0, to: Orientation.self) }
        connection = resolve("CGSMainConnectionID").map { unsafeBitCast($0, to: Connection.self) }
        capture = resolve("CGSHWCaptureWindowList").map { unsafeBitCast($0, to: Capture.self) }
        windowID = resolve("_AXUIElementGetWindow").map { unsafeBitCast($0, to: WindowID.self) }
    }

    var supportsCapture: Bool { connection != nil && capture != nil }
    var supportsWindowIDs: Bool { windowID != nil }

    func dockOrientation(_ output: UnsafeMutablePointer<Int32>, pinning: UnsafeMutablePointer<Int32>) {
        output.pointee = 0
        pinning.pointee = 0
        orientation?(output, pinning)
    }

    func mainConnection() -> UInt32 { connection?() ?? 0 }

    func captureWindows(_ connectionID: UInt32, windows: UnsafePointer<UInt32>, count: UInt32,
                        options: CGSWindowCaptureOptions) -> CFArray? {
        guard supportsCapture, connectionID != 0, count > 0 else { return nil }
        return capture?(connectionID, windows, count, options.rawValue)?.takeRetainedValue()
    }

    func getWindowID(_ element: AXUIElement, output: UnsafeMutablePointer<CGWindowID>) -> AXError {
        output.pointee = 0
        guard let windowID else { return .notImplemented }
        return windowID(element, output)
    }
}

func CGSMainConnectionID() -> CGSConnectionID { PrivateWindowSymbols.shared.mainConnection() }

func CGSHWCaptureWindowList(_ connection: CGSConnectionID, _ windows: UnsafePointer<UInt32>,
                           _ count: CGSWindowCount, _ options: CGSWindowCaptureOptions) -> CFArray? {
    PrivateWindowSymbols.shared.captureWindows(connection, windows: windows, count: count, options: options)
}

enum DockPosition {
    case bottom, left, right, top, unknown

    static var current: DockPosition {
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        PrivateWindowSymbols.shared.dockOrientation(&orientation, pinning: &pinning)
        switch orientation {
        case 1: return .top
        case 2: return .bottom
        case 3: return .left
        case 4: return .right
        default: return .bottom
        }
    }
}
