import AppKit

// Private CoreDock symbol used to learn where the Dock is (bottom/left/right).
// Same approach DockDoor/AltTab use; stable for many macOS releases.
@_silgen_name("CoreDockGetOrientationAndPinning")
func CoreDockGetOrientationAndPinning(_ outOrientation: UnsafeMutablePointer<Int32>,
                                      _ outPinning: UnsafeMutablePointer<Int32>)

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

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: CGSConnectionID,
                           _ windowList: UnsafePointer<UInt32>,
                           _ count: CGSWindowCount,
                           _ options: CGSWindowCaptureOptions) -> CFArray?

enum DockPosition {
    case bottom, left, right, top, unknown

    static var current: DockPosition {
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        CoreDockGetOrientationAndPinning(&orientation, &pinning)
        switch orientation {
        case 1: return .top
        case 2: return .bottom
        case 3: return .left
        case 4: return .right
        default: return .bottom
        }
    }
}
