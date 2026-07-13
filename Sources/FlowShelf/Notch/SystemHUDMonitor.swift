import AppKit
import CoreAudio
import AudioToolbox
import IOKit.hid

/// Catches the hardware volume/brightness keys and turns them into notch HUDs.
/// Reads the actual level (volume via CoreAudio; brightness via a private
/// DisplayServices symbol, best-effort on Apple Silicon) and — per the user's
/// choice — suppresses macOS's own centred overlay by killing OSDUIHelper.
@MainActor
final class SystemHUDMonitor {
    static let shared = SystemHUDMonitor()

    var onEvent: ((NotchHUD) -> Void)?
    /// Suppress Apple's centred overlay by force-quitting OSDUIHelper per keypress.
    var hideSystemOverlay = true

    private var globalMon: Any?
    private var localMon: Any?
    private var running = false
    private var getBrightness: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32)?

    // NX_KEYTYPE codes carried in the systemDefined event's data1.
    private let kSoundUp = 0, kSoundDown = 1, kBrightnessUp = 2, kBrightnessDown = 3, kMute = 7

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        // Prompt for Input Monitoring so the global key monitor can see the keys.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        loadBrightnessSymbol()

        let handler: (NSEvent) -> Void = { [weak self] ev in self?.handle(ev) }
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { handler($0) }
        localMon = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { handler($0); return $0 }
    }

    func stop() {
        running = false
        if let g = globalMon { NSEvent.removeMonitor(g) }
        if let l = localMon { NSEvent.removeMonitor(l) }
        globalMon = nil; localMon = nil
    }

    // MARK: Key handling

    private func handle(_ ev: NSEvent) {
        guard ev.subtype.rawValue == 8 else { return }   // NX aux control buttons
        let data1 = ev.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else { return }            // key DOWN only

        switch keyCode {
        case kSoundUp, kSoundDown, kMute:
            suppressSystemOverlay()
            let (level, muted) = Self.outputVolume()
            onEvent?(.volume(level, muted: muted))
        case kBrightnessUp, kBrightnessDown:
            suppressSystemOverlay()
            onEvent?(.brightness(displayBrightness()))
        default:
            break
        }
    }

    /// The key press just changed the value; give the system a beat to settle,
    /// then read — and repeatedly kill OSDUIHelper so its overlay never lands.
    private func suppressSystemOverlay() {
        guard hideSystemOverlay else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.OSDUIHelper") {
            app.forceTerminate()
        }
    }

    // MARK: Level readers

    /// System output volume (0…1) and mute state, via the default output device.
    static func outputVolume() -> (Double, Bool) {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &devAddr, 0, nil, &size, &device) == noErr else { return (0, false) }

        var vol = Float32(0)
        var vsize = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &volAddr, 0, nil, &vsize, &vol)

        var muted = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &muteAddr) {
            AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &msize, &muted)
        }
        return (Double(vol), muted != 0)
    }

    /// Built-in display brightness (0…1). Private DisplayServices symbol; if it's
    /// unavailable we fall back to a neutral value so the HUD still appears.
    private func displayBrightness() -> Double {
        guard let getBrightness else { return 0.5 }
        var value: Float = 0.5
        _ = getBrightness(CGMainDisplayID(), &value)
        return Double(min(max(value, 0), 1))
    }

    private func loadBrightnessSymbol() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(sym, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self)
    }
}
