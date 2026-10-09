import AppKit
import ScreenCaptureKit
import CoreMedia
import AudioToolbox
import Accelerate

@MainActor
final class AudioSpectrum: ObservableObject {
    static let shared = AudioSpectrum()

    /// 0…1 smoothed loudness; `active` is true while the tap runs.
    @Published private(set) var level: Float = 0
    @Published private(set) var bands: [Float] = Array(repeating: 0, count: 6)
    @Published private(set) var active = false
    @Published private(set) var statusMessage = "Compatibility capture. Process taps are optional and experimental."
    @Published private(set) var isStarting = false

    private var stream: SCStream?
    private var output: TapOutput?
    private var wantActive = false
    private var screenLocked = false
    private var sleeping = false
    private var generation = UUID()
    private var attempted = false
    private var mode = NotchAudioCaptureMode.compatibility
    private var playerBundleID = ""
    private var processTap: ProcessAudioTapSession?
    private var processTimer: Timer?
    private var lastSpectrumAt = Date.distantPast
    private let processTapFactory: (() -> ProcessAudioTapSession)?

    var canRetry: Bool { wantActive && !screenLocked && !sleeping && !isStarting }

    init(processTapFactory: (() -> ProcessAudioTapSession)? = nil, observeSystemEvents: Bool = true) {
        self.processTapFactory = processTapFactory
        guard observeSystemEvents else { return }
        // Pause the tap while the screen is locked — no one can see the bars,
        // and there's no reason to hold the recording indicator either.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setScreenLocked(true) }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setScreenLocked(false) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(true) }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(false) }
        }
    }

    func setScreenLocked(_ locked: Bool) {
        screenLocked = locked
        if locked { stopCapture(message: "Audio capture paused while locked.") }
        else { start() }
    }

    func setSleeping(_ asleep: Bool) {
        sleeping = asleep
        if asleep { stopCapture(message: "Audio capture paused while sleeping.") }
        else { start() }
    }

    private func stopCapture(message: String = "Audio capture is idle.") {
        generation = UUID()
        attempted = false
        isStarting = false
        processTimer?.invalidate()
        processTimer = nil
        processTap?.stop()
        processTap = nil
        lastSpectrumAt = .distantPast
        let streamToStop = stream
        stream = nil; output = nil
        active = false
        level = 0
        resetEnvelope()
        statusMessage = message
        if let streamToStop {
            Task { try? await streamToStop.stopCapture() }
        }
    }

    /// Called by MediaManager as playback starts/stops.
    func setActive(_ on: Bool, playerBundleID: String = "") {
        let requestedMode = AppSettings.shared.notchAudioCaptureMode
        let requestedPlayer = requestedMode == .playerTap ? playerBundleID : ""
        if !on || !wantActive || mode != requestedMode || self.playerBundleID != requestedPlayer {
            stopCapture()
        }
        mode = requestedMode
        self.playerBundleID = requestedPlayer
        wantActive = on
        if on { start() }
    }

    func retry() {
        guard canRetry else { return }
        stopCapture()
        start()
    }

    private func start() {
        guard wantActive, !screenLocked, !sleeping, !attempted else { return }
        attempted = true
        isStarting = true
        let session = generation
        if mode != .compatibility {
            startProcessTap(session: session)
            return
        }
        guard Permissions.hasScreenRecording else {
            isStarting = false
            statusMessage = "Compatibility capture needs Screen Recording permission. Grant it, then Retry."
            return
        }
        statusMessage = "Starting compatibility audio capture…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard self.generation == session, self.wantActive, !self.screenLocked, !self.sleeping else { return }
                guard let display = content.displays.first else {
                    self.isStarting = false
                    self.statusMessage = "No display is available for compatibility capture. Retry when a display is connected."
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                // Video is mandatory on the stream; keep it as small and slow as
                // possible — we never attach a video output.
                cfg.width = 2; cfg.height = 2
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

                let out = TapOutput { [weak self] rms, bands in
                    Task { @MainActor in
                        guard let self, self.generation == session, self.active else { return }
                        self.ingest(rms, bands: bands)
                    }
                } onFailure: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == session else { return }
                        self.stopCapture(message: "Compatibility audio capture stopped. Retry to reconnect.")
                        self.attempted = true
                    }
                }
                let stream = SCStream(filter: filter, configuration: cfg, delegate: out)
                try stream.addStreamOutput(out, type: .audio,
                                           sampleHandlerQueue: DispatchQueue(label: "flowshelf.audiotap"))
                try await stream.startCapture()
                guard self.generation == session, self.wantActive, !self.screenLocked, !self.sleeping else {
                    try? await stream.stopCapture()
                    return
                }
                self.isStarting = false
                self.stream = stream
                self.output = out
                self.active = true
                self.statusMessage = "Compatibility capture connected (system mix)."
            } catch {
                guard self.generation == session else { return }
                self.isStarting = false
                self.statusMessage = "Compatibility capture unavailable. Check Screen Recording permission, then Retry."
            }
        }
    }

    private func startProcessTap(session: UUID) {
        guard #available(macOS 14.4, *) else {
            isStarting = false
            statusMessage = "Process taps require macOS 14.4 or later. Choose Compatibility."
            return
        }
        statusMessage = "Starting process tap… macOS may ask for audio-recording permission."
        let tap = processTapFactory?() ?? ProcessAudioTap()
        processTap = tap
        tap.start(playerBundleID: mode == .playerTap ? playerBundleID : nil) { [weak self] failure in
            Task { @MainActor in
                guard let self, self.generation == session else { tap.stop(); return }
                self.isStarting = false
                if let failure {
                    self.stopCapture(message: failure)
                    self.attempted = true
                    return
                }
                self.statusMessage = "Process tap connected; waiting for audio buffers…"
                let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.generation == session else { return }
                        self.pollProcessTap()
                    }
                }
                self.processTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func pollProcessTap() {
        guard let result = processTap?.takeResult() else { return }
        if let failure = result.failure {
            stopCapture(message: failure)
            attempted = true
        } else if let (rms, bands) = result.spectrum {
            lastSpectrumAt = Date()
            if !active { active = true }
            ingest(rms, bands: bands)
            let message = rms > 0.00001
                ? "Process tap receiving audio (\(mode == .playerTap ? playerBundleID : "system mix"))."
                : "Process tap connected, but no audible signal. Check the player and audio-recording permission if this persists."
            if statusMessage != message { statusMessage = message }
        } else if active, Date().timeIntervalSince(lastSpectrumAt) > 0.15 {
            ingest(0, bands: Array(repeating: 0, count: 6))
        }
    }

    // Envelope state (main actor; fed at ≤ ~20Hz by TapOutput's throttle).
    private var envelope: Float = 0
    private var runningPeak: Float = 0.05
    private var runningAverage: Float = 0.01
    private var bandEnvelopes: [Float] = Array(repeating: 0, count: 6)
    private var bandPeaks: [Float] = Array(repeating: 0.001, count: 6)
    private var bandAverages: [Float] = Array(repeating: 0.0001, count: 6)

    private func resetEnvelope() {
        envelope = 0
        runningPeak = 0.05
        runningAverage = 0.01
        bandEnvelopes = Array(repeating: 0, count: 6)
        bandPeaks = Array(repeating: 0.001, count: 6)
        bandAverages = Array(repeating: 0.0001, count: 6)
        bands = Array(repeating: 0, count: 6)
    }

    private func ingest(_ rms: Float, bands rawBands: [Float]) {
        runningPeak = max(rms, runningPeak * 0.97, 0.02)
        runningAverage += (rms - runningAverage) * 0.08
        let loudness = min(rms / runningPeak, 1)
        let transientRange = max(runningPeak - runningAverage, 0.005)
        let transient = min(max((rms - runningAverage) / transientRange, 0), 1)
        let target = min(loudness * 0.66 + transient * 0.52, 1)
        envelope = target > envelope ? envelope + (target - envelope) * 0.80
                                     : envelope + (target - envelope) * 0.30
        level = envelope

        var smoothedBands = bandEnvelopes
        for index in 0..<min(rawBands.count, smoothedBands.count) {
            let raw = rawBands[index]
            bandPeaks[index] = max(raw, bandPeaks[index] * 0.96, 0.000001)
            bandAverages[index] += (raw - bandAverages[index]) * 0.08
            let loudness = min(raw / bandPeaks[index], 1)
            let transientRange = max(bandPeaks[index] - bandAverages[index], 0.000001)
            let transient = min(max((raw - bandAverages[index]) / transientRange, 0), 1)
            let target = min(loudness * 0.72 + transient * 0.42, 1)
            let current = bandEnvelopes[index]
            smoothedBands[index] = target > current
                ? current + (target - current) * 0.76
                : current + (target - current) * 0.24
        }
        bandEnvelopes = smoothedBands
        bands = smoothedBands
    }

    /// Audio-thread side: buffers → RMS, throttled to ~20 updates/s.
    private final class TapOutput: NSObject, SCStreamOutput, SCStreamDelegate {
        private let onSpectrum: (Float, [Float]) -> Void
        private let onFailure: () -> Void
        private let analyzer = FrequencyAnalyzer()
        private var lastEmit = CFAbsoluteTimeGetCurrent()
        init(onSpectrum: @escaping (Float, [Float]) -> Void, onFailure: @escaping () -> Void) {
            self.onSpectrum = onSpectrum
            self.onFailure = onFailure
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure() }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                    of type: SCStreamOutputType) {
            guard type == .audio else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastEmit >= 1.0 / 20.0 else { return }
            lastEmit = now

            let sampleRate: Float
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                sampleRate = Float(description.pointee.mSampleRate)
            } else {
                sampleRate = 48_000
            }
            let analyzed: (rms: Float, bands: [Float])?
            do {
                analyzed = try sampleBuffer.withAudioBufferList { list, _ in
                    analyzer.analyze(list, sampleRate: sampleRate)
                }
            } catch {
                return
            }
            guard let result = analyzed else { return }
            onSpectrum(result.rms, result.bands)
        }
    }

    private final class FrequencyAnalyzer {
        private let sampleCount = 512
        private let halfCount = 256
        private let log2n = vDSP_Length(9)
        private let fftSetup: FFTSetup
        private let window: [Float]
        private var mono = [Float](repeating: 0, count: 512)
        private var windowed = [Float](repeating: 0, count: 512)
        private var real = [Float](repeating: 0, count: 256)
        private var imaginary = [Float](repeating: 0, count: 256)
        private var magnitudes = [Float](repeating: 0, count: 256)

        init() {
            fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
            window = vDSP.window(ofType: Float.self,
                                 usingSequence: .hanningDenormalized,
                                 count: sampleCount,
                                 isHalfWindow: false)
        }

        deinit { vDSP_destroy_fftsetup(fftSetup) }

        func analyze(_ list: UnsafeMutableAudioBufferListPointer,
                     sampleRate: Float) -> (rms: Float, bands: [Float])? {
            mono.withUnsafeMutableBufferPointer { pointer in
                vDSP_vclr(pointer.baseAddress!, 1, vDSP_Length(sampleCount))
            }
            var channelCount: Float = 0
            var populatedSamples = 0
            for buffer in list {
                guard let data = buffer.mData else { continue }
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let count = min(available, sampleCount)
                guard count > 0 else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count { mono[index] += samples[index] }
                channelCount += 1
                populatedSamples = max(populatedSamples, count)
            }
            guard channelCount > 0, populatedSamples > 0 else { return nil }

            var divisor = channelCount
            vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(populatedSamples))
            var rms: Float = 0
            vDSP_rmsqv(mono, 1, &rms, vDSP_Length(populatedSamples))
            vDSP_vmul(mono, 1, window, 1, &windowed, 1, vDSP_Length(sampleCount))

            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                                imagp: imaginaryPointer.baseAddress!)
                    windowed.withUnsafeBytes { bytes in
                        let complex = bytes.bindMemory(to: DSPComplex.self).baseAddress!
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(halfCount))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n,
                                  FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfCount))
                }
            }
            magnitudes[0] = 0

            let ranges: [(Float, Float)] = [
                (45, 140), (140, 320), (320, 800),
                (800, 2_200), (2_200, 5_200), (5_200, 16_000),
            ]
            let binWidth = sampleRate / Float(sampleCount)
            let bands = ranges.map { lower, upper -> Float in
                let first = max(1, min(halfCount - 1, Int(ceil(lower / binWidth))))
                let last = max(first, min(halfCount - 1, Int(floor(upper / binWidth))))
                var sum: Float = 0
                for bin in first...last { sum += magnitudes[bin] }
                return sqrt(sum / Float(last - first + 1))
            }
            return (rms, bands)
        }
    }
}
