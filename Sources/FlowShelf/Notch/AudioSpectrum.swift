import AppKit
import ScreenCaptureKit
import CoreMedia
import AudioToolbox
import Accelerate

/// Live loudness of what the Mac is actually playing, so the notch's audio bars
/// dance to the REAL music instead of a canned sine loop.
///
/// Taps system audio with ScreenCaptureKit (`capturesAudio` — covered by the
/// same Screen Recording permission the notch lens already uses; our own audio
/// is excluded). Each buffer is reduced to one RMS loudness value with a fast
/// attack / slow release envelope, normalised against a slowly-decaying running
/// peak so quiet tracks still move the bars. Cost: a few thousand multiplies per
/// 10ms buffer on the audio thread — no GPU involved at all.
@MainActor
final class AudioSpectrum: ObservableObject {
    static let shared = AudioSpectrum()

    /// 0…1 smoothed loudness; `active` is true while the tap runs.
    @Published private(set) var level: Float = 0
    @Published private(set) var bands: [Float] = Array(repeating: 0, count: 6)
    @Published private(set) var active = false

    private var stream: SCStream?
    private var output: TapOutput?
    private var starting = false
    private var wantActive = false
    private var screenLocked = false

    private init() {
        // Pause the tap while the screen is locked — no one can see the bars,
        // and there's no reason to hold the recording indicator either.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                AudioSpectrum.shared.screenLocked = true
                AudioSpectrum.shared.stopForLock()
            }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                AudioSpectrum.shared.screenLocked = false
                if AudioSpectrum.shared.wantActive { AudioSpectrum.shared.start() }
            }
        }
    }

    private func stopForLock() {
        let streamToStop = stream
        stream = nil; output = nil
        active = false
        level = 0
        resetEnvelope()
        if let streamToStop {
            Task { try? await streamToStop.stopCapture() }
        }
    }

    /// Called by MediaManager as playback starts/stops.
    func setActive(_ on: Bool) {
        wantActive = on
        if on, !screenLocked { start() } else { stop() }
    }

    private func start() {
        guard stream == nil, !starting, Permissions.hasScreenRecording else { return }
        starting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    self.starting = false; return
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
                    Task { @MainActor in self?.ingest(rms, bands: bands) }
                }
                let stream = SCStream(filter: filter, configuration: cfg, delegate: out)
                try stream.addStreamOutput(out, type: .audio,
                                           sampleHandlerQueue: DispatchQueue(label: "flowshelf.audiotap"))
                try await stream.startCapture()
                self.starting = false
                guard self.wantActive else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                self.output = out
                self.active = true
            } catch {
                self.starting = false
                NSLog("AudioSpectrum: tap unavailable: \(error)")
            }
        }
    }

    private func stop() {
        let streamToStop = stream
        stream = nil; output = nil
        active = false
        level = 0
        resetEnvelope()
        if let streamToStop {
            Task { try? await streamToStop.stopCapture() }
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
        private let analyzer = FrequencyAnalyzer()
        private var lastEmit = CFAbsoluteTimeGetCurrent()
        init(onSpectrum: @escaping (Float, [Float]) -> Void) { self.onSpectrum = onSpectrum }

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
