import AppKit
import CoreAudio
import AudioToolbox
import IOKit.hid

/// Catches the hardware volume/brightness keys and turns them into notch HUDs.
/// Reads the actual level (volume via CoreAudio; brightness via a private
/// DisplayServices symbol, best-effort on Apple Silicon).
@MainActor
final class SystemHUDMonitor {
    static let shared = SystemHUDMonitor()

    var onEvent: ((NotchHUD) -> Void)?
    private var globalMon: Any?
    private var localMon: Any?
    private var running = false
    private var pendingRead: DispatchWorkItem?
    private var readGeneration = UUID()

    // NX_KEYTYPE codes carried in the systemDefined event's data1.
    private let kSoundUp = 0, kSoundDown = 1, kBrightnessUp = 2, kBrightnessDown = 3, kMute = 7

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        // Prompt for Input Monitoring so the global key monitor can see the keys.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        let handler: (NSEvent) -> Void = { [weak self] ev in self?.handle(ev) }
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { handler($0) }
        localMon = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { handler($0); return $0 }
    }

    func stop() {
        running = false
        readGeneration = UUID()
        pendingRead?.cancel()
        pendingRead = nil
        if let g = globalMon { NSEvent.removeMonitor(g) }
        if let l = localMon { NSEvent.removeMonitor(l) }
        globalMon = nil; localMon = nil
    }

    // MARK: Key handling

    private func handle(_ ev: NSEvent) {
        guard running, ev.subtype.rawValue == 8 else { return }   // NX aux control buttons
        let data1 = ev.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else { return }            // key DOWN only

        guard [kSoundUp, kSoundDown, kMute, kBrightnessUp, kBrightnessDown].contains(keyCode) else { return }
        pendingRead?.cancel()
        readGeneration = UUID()
        let generation = readGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.readGeneration == generation else { return }
            self.pendingRead = nil
            if [self.kSoundUp, self.kSoundDown, self.kMute].contains(keyCode) {
                guard let (level, muted) = Self.outputVolume() else { return }
                self.onEvent?(.volume(level, muted: muted))
            } else {
                guard let level = HUDBrightnessReader.shared.level(displayID: CGMainDisplayID()) else { return }
                self.onEvent?(.brightness(level))
            }
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    // MARK: Level readers

    /// System output volume (0…1) and mute state, via the default output device.
    static func outputVolume() -> (Double, Bool)? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &devAddr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        var vol = Float32.nan
        var vsize = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &volAddr),
              AudioObjectGetPropertyData(device, &volAddr, 0, nil, &vsize, &vol) == noErr,
              let level = HUDLevelValidation.normalized(vol, status: 0) else { return nil }

        var muted = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &muteAddr) {
            guard AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &msize, &muted) == noErr else { return nil }
        }
        return (level, muted != 0)
    }
}
