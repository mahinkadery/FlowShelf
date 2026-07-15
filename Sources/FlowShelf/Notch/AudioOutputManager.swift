import AppKit
import CoreAudio

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    /// A representative SF Symbol for the device kind (headphones, speaker, etc.).
    var icon: String {
        let n = name.lowercased()
        if n.contains("airpod") { return "airpodspro" }
        if n.contains("headphone") || n.contains("beats") { return "headphones" }
        if n.contains("display") || n.contains("monitor") || n.contains("tv") { return "tv" }
        if n.contains("macbook") || n.contains("built-in") || n.contains("internal") { return "laptopcomputer" }
        return "hifispeaker.fill"
    }
}

/// Lists and switches the system audio output device (CoreAudio) — used by the
/// notch's output switcher.
@MainActor
final class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var currentID: AudioDeviceID = 0
    /// The inline device list (iOS-style) is expanded in the notch.
    @Published var pickerOpen = false
    /// Volume of the CURRENT output device (0…1), or nil when the device offers
    /// no volume control (e.g. DisplayLink/HDMI sinks controlled by the monitor).
    @Published private(set) var volume: Float?

    private var listenersInstalled = false

    private init() {}

    /// Track the system's real state: if the default output or the device list
    /// changes behind our back (AirPods connect, dock unplugged), follow it.
    private func installListeners() {
        guard !listenersInstalled else { return }
        listenersInstalled = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let onChange: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in AudioOutputManager.shared.refresh() }
        }
        AudioObjectAddPropertyListenerBlock(system, &defAddr, DispatchQueue.main, onChange)
        AudioObjectAddPropertyListenerBlock(system, &devAddr, DispatchQueue.main, onChange)
    }

    var currentName: String { devices.first { $0.id == currentID }?.name ?? "Output" }
    var currentIcon: String { devices.first { $0.id == currentID }?.icon ?? "hifispeaker.fill" }

    func refresh() {
        installListeners()
        devices = outputDevices()
        currentID = defaultOutputDevice()
        volume = readVolume(currentID)
    }

    func select(_ id: AudioDeviceID) {
        guard setDefaultOutput(id) else { return }
        // Read BACK rather than assume — some devices refuse the switch.
        currentID = defaultOutputDevice()
        volume = readVolume(currentID)
    }

    // MARK: Volume of the current device

    func setVolume(_ v: Float) {
        let clamped = max(0, min(1, v))
        writeVolume(currentID, clamped)
        volume = readVolume(currentID) ?? clamped
    }

    private func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private func readVolume(_ id: AudioDeviceID) -> Float? {
        var v = Float32(0); var size = UInt32(4)
        // Main element first; stereo devices often expose only channels 1/2.
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var a = volumeAddress(element)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    private func writeVolume(_ id: AudioDeviceID, _ v: Float) {
        var value = Float32(v)
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = volumeAddress(element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(id, &a, &settable) == noErr, settable.boolValue else { continue }
            AudioObjectSetPropertyData(id, &a, 0, nil, 4, &value)
        }
    }

    // MARK: CoreAudio

    private func defaultOutputDevice() -> AudioDeviceID {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return dev
    }

    @discardableResult
    private func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var dev = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &dev) == noErr
    }

    private func outputDevices() -> [AudioOutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }

        return ids.compactMap { id in
            guard hasOutput(id), let name = deviceName(id) else { return nil }
            return AudioOutputDevice(id: id, name: name)
        }
    }

    private func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return size > 0
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &cfName) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let cf = cfName else { return nil }
        return cf.takeRetainedValue() as String
    }
}
