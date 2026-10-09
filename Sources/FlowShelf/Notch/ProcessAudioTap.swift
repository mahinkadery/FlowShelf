import CoreAudio
import Foundation

enum NotchAudioCaptureMode: String, CaseIterable, Identifiable {
    case compatibility, systemTap, playerTap
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compatibility: return "Compatibility (ScreenCaptureKit)"
        case .systemTap: return "System audio (experimental tap)"
        case .playerTap: return "Current player only (experimental tap)"
        }
    }
}

protocol ProcessAudioTapSession: AnyObject {
    func start(playerBundleID: String?, completion: @escaping @Sendable (String?) -> Void)
    func stop()
    func takeResult() -> (spectrum: (Float, [Float])?, failure: String?)
}

@available(macOS 14.4, *)
final class ProcessAudioTap: ProcessAudioTapSession, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.flowshelf.process-audio-tap", qos: .utility)
    private let ioQueue = DispatchQueue(label: "app.flowshelf.process-audio-io", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var observers: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var latest: (Float, [Float])?
    private let resultLock = NSLock()
    private var failure: String?
    private var cancelled = false
    private var lastBufferAt = Date.distantPast

    func start(playerBundleID: String?, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            do {
                try ensureNotCancelled()
                try create(playerBundleID: playerBundleID)
                completion(nil)
            } catch {
                destroy()
                completion(error.localizedDescription)
            }
        }
    }

    func stop() {
        resultLock.lock()
        cancelled = true
        resultLock.unlock()
        queue.async { [self] in destroy() }
    }

    private func ensureNotCancelled() throws {
        resultLock.lock()
        let shouldCancel = cancelled
        resultLock.unlock()
        if shouldCancel { throw CancellationError() }
    }

    func takeResult() -> (spectrum: (Float, [Float])?, failure: String?) {
        resultLock.lock()
        defer { resultLock.unlock() }
        let result = (latest, failure)
        latest = nil
        return result
    }

    private struct TapError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw TapError(message: "\(operation) failed (\(status)). Check macOS audio-recording permission, then Retry or choose Compatibility.")
        }
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func processID(for pid: pid_t) throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = pid
        var result = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property,
                                            UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &result), "Finding audio process")
        return result
    }

    private func playerProcesses(bundleID: String) throws -> [AudioObjectID] {
        guard !bundleID.isEmpty else { throw TapError(message: "No current player identified. Select System audio explicitly or wait for a supported player.") }
        var property = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size), "Listing audio processes")
        guard size > 0, size <= 1_048_576 else { throw TapError(message: "No audio processes are available. Start playback, then Retry.") }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try processes.withUnsafeMutableBytes { bytes in
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, bytes.baseAddress!), "Reading audio processes")
        }
        let matches = processes.filter { process in
            var property = address(kAudioProcessPropertyBundleID)
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &property, 0, nil, &size, &value) == noErr,
                  let value else { return false }
            return value.takeRetainedValue() as String == bundleID
        }
        guard !matches.isEmpty else { throw TapError(message: "This player's audio process could not be isolated. Browser/helper processes may not match. Retry after playback starts, or explicitly choose System audio.") }
        return matches
    }

    private func create(playerBundleID: String?) throws {
        let description: CATapDescription
        if let playerBundleID {
            description = CATapDescription(stereoMixdownOfProcesses: try playerProcesses(bundleID: playerBundleID))
            if #available(macOS 26.0, *) {
                description.bundleIDs = [playerBundleID]
                description.isProcessRestoreEnabled = true
            }
        } else {
            let ownProcess = try processID(for: getpid())
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcess == kAudioObjectUnknown ? [] : [ownProcess])
        }
        description.name = "FlowShelf notch spectrum"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try ensureNotCancelled()
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating audio tap")
        var property = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &property, 0, nil, &size, &format), "Reading audio format")
        guard let buffer = ProcessTapSpectrumBuffer(format: format), let analyzer = ProcessTapSpectrumAnalyzer() else {
            throw TapError(message: "This audio format is unsupported by the prototype. Choose Compatibility instead.")
        }
        let device: [String: Any] = [
            kAudioAggregateDeviceNameKey: "FlowShelf spectrum (private)",
            kAudioAggregateDeviceUIDKey: "app.flowshelf.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID), "Creating audio device")
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, ioQueue) { _, input, _, _, _ in
            buffer.append(input)
        }, "Connecting audio callback")
        guard ioProc != nil else { throw TapError(message: "Audio callback was not created. Choose Compatibility or Retry.") }
        try observe(tapID, selector: kAudioTapPropertyFormat)
        try observe(deviceID, selector: kAudioDevicePropertyDeviceIsAlive)
        try observe(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
        try ensureNotCancelled()
        try check(AudioDeviceStart(deviceID, ioProc), "Starting audio capture")
        try ensureNotCancelled()
        lastBufferAt = Date()
        let sampleRate = Float(format.mSampleRate)
        let channels = Int(format.mChannelsPerFrame)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let samples = buffer.takeWindow(), let spectrum = analyzer.analyze(samples, sampleRate: sampleRate, channels: channels) {
                lastBufferAt = Date()
                resultLock.lock()
                latest = spectrum
                resultLock.unlock()
            } else if Date().timeIntervalSince(lastBufferAt) > 6 {
                fail("No audio buffers received. Check audio-recording permission and the player/output, then Retry.")
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func observe(_ object: AudioObjectID, selector: AudioObjectPropertySelector) throws {
        var property = address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.deviceID != kAudioObjectUnknown else { return }
            if selector == kAudioDevicePropertyDeviceIsAlive {
                var property = self.address(selector)
                var alive: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(object, &property, 0, nil, &size, &alive) == noErr, alive != 0 { return }
            }
            self.fail("Audio output or format changed. Retry to reconnect, or choose Compatibility.")
        }
        try check(AudioObjectAddPropertyListenerBlock(object, &property, queue, block), "Monitoring audio changes")
        observers.append((object, property, block))
    }

    private func fail(_ message: String) {
        destroy()
        resultLock.lock()
        failure = message
        resultLock.unlock()
    }

    private func destroy() {
        timer?.cancel()
        timer = nil
        for (object, original, block) in observers {
            var property = original
            AudioObjectRemovePropertyListenerBlock(object, &property, queue, block)
        }
        observers.removeAll()
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
        }
        ioProc = nil
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        resultLock.lock()
        latest = nil
        resultLock.unlock()
    }
}
