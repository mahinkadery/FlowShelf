import AppKit
import CoreAudio
import Combine

struct NotchAudioRoute: Equatable {
    let uid: String
    let name: String
    let bluetooth: Bool

    var icon: String {
        let lower = name.lowercased()
        if lower.contains("airpods") {
            if lower.contains("max") { return "airpodsmax" }
            return lower.contains("pro") ? "airpodspro" : "airpods"
        }
        if lower.contains("headphone") || lower.contains("beats") { return "headphones" }
        if lower.contains("display") || lower.contains("hdmi") { return "display" }
        if lower.contains("macbook") || lower.contains("built-in") { return "laptopcomputer" }
        return "hifispeaker.fill"
    }
}

struct NotchSystemEventState {
    private var route: NotchAudioRoute?
    private var lowPower = false

    mutating func seed(route: NotchAudioRoute?, lowPower: Bool) {
        self.route = route
        self.lowPower = lowPower
    }

    mutating func changeRoute(_ next: NotchAudioRoute?) -> NotchHUD? {
        guard let next else { return nil }
        defer { route = next }
        guard next.uid != route?.uid else { return nil }
        return .audioRoute(name: next.name, icon: next.icon, bluetooth: next.bluetooth)
    }

    mutating func changePower(_ enabled: Bool) -> NotchHUD? {
        guard lowPower != enabled else { return nil }
        lowPower = enabled
        return .lowPowerMode(enabled)
    }
}

@MainActor
final class NotchSystemEvents {
    static let shared = NotchSystemEvents()
    var onEvent: ((NotchHUD) -> Void)?
    var onSuspend: (() -> Void)?
    private var running = false
    private var generation = UUID()
    private var state = NotchSystemEventState()
    private var audioListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var powerObserver: NSObjectProtocol?
    private var suspensionObserver: AnyCancellable?
    private var pendingRead: DispatchWorkItem?

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        seed()
        let session = generation
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.running, self.generation == session else { return }
                    self.scheduleRead()
                }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                                   .main, listener) == noErr {
                audioListeners.append((address, listener))
            }
        }
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.running, self.generation == session,
                          !NotchPresentationState.shared.suspended else { return }
                    if let event = self.state.changePower(ProcessInfo.processInfo.isLowPowerModeEnabled) {
                        self.onEvent?(event)
                    }
                }
            }
        suspensionObserver = NotchPresentationState.shared.$suspended
            .receive(on: RunLoop.main).sink { [weak self] suspended in
                guard let self, self.running, self.generation == session else { return }
                self.pendingRead?.cancel()
                self.pendingRead = nil
                if suspended { self.onSuspend?() } else { self.seed() }
            }
    }

    func stop() {
        running = false
        generation = UUID()
        pendingRead?.cancel()
        pendingRead = nil
        for (original, listener) in audioListeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        audioListeners.removeAll()
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        powerObserver = nil
        suspensionObserver = nil
    }

    private func seed() {
        state.seed(route: Self.readRoute(), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private func scheduleRead() {
        guard !NotchPresentationState.shared.suspended else { return }
        pendingRead?.cancel()
        let session = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.generation == session,
                  !NotchPresentationState.shared.suspended else { return }
            self.pendingRead = nil
            if let event = self.state.changeRoute(Self.readRoute()) { self.onEvent?(event) }
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private static func readRoute() -> NotchAudioRoute? {
        var device: AudioDeviceID = 0
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device),
              device != kAudioObjectUnknown,
              let uid = string(device, kAudioDevicePropertyDeviceUID),
              let name = string(device, kAudioObjectPropertyName) else { return nil }
        var transport: UInt32 = 0
        _ = read(device, kAudioDevicePropertyTransportType, into: &transport)
        let cleanName = String(name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(64))
        return NotchAudioRoute(uid: uid, name: cleanName.isEmpty ? "Audio device" : cleanName,
            bluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
    }

    private static func read(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             into value: inout UInt32) -> Bool {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
