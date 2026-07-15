import AppKit
import ScreenCaptureKit
import CoreMedia

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
        stream?.stopCapture { _ in }
        stream = nil; output = nil
        active = false
        level = 0
    }

    /// Called by MediaManager as playback starts/stops.
    func setActive(_ on: Bool) {
        wantActive = on
        if on, !screenLocked { start() } else { stop() }
    }

    private func start() {
        guard stream == nil, !starting else { return }
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

                let out = TapOutput { [weak self] rms in
                    Task { @MainActor in self?.ingest(rms) }
                }
                let stream = SCStream(filter: filter, configuration: cfg, delegate: out)
                try stream.addStreamOutput(out, type: .audio,
                                           sampleHandlerQueue: DispatchQueue(label: "flowshelf.audiotap"))
                try await stream.startCapture()
                self.starting = false
                guard self.wantActive else { stream.stopCapture { _ in }; return }
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
        stream?.stopCapture { _ in }
        stream = nil; output = nil
        active = false
        level = 0
    }

    // Envelope state (main actor; fed at ≤ ~30Hz by TapOutput's throttle).
    private var envelope: Float = 0
    private var runningPeak: Float = 0.05

    private func ingest(_ rms: Float) {
        // Normalise against a slow-decaying peak → dynamics survive any volume.
        runningPeak = max(rms, runningPeak * 0.995, 0.02)
        let norm = min(rms / runningPeak, 1)
        // Fast attack, slower release — the shape that reads as "beat".
        envelope = norm > envelope ? envelope + (norm - envelope) * 0.55
                                   : envelope + (norm - envelope) * 0.18
        level = envelope
    }

    /// Audio-thread side: buffers → RMS, throttled to ~30 updates/s.
    private final class TapOutput: NSObject, SCStreamOutput, SCStreamDelegate {
        private let onRMS: (Float) -> Void
        private var lastEmit = CFAbsoluteTimeGetCurrent()
        init(onRMS: @escaping (Float) -> Void) { self.onRMS = onRMS }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                    of type: SCStreamOutputType) {
            guard type == .audio else { return }
            // SCK audio is stereo NON-interleaved — a fixed single-buffer
            // AudioBufferList fails every call (-12737, list too small); the
            // Swift overlay sizes the list correctly for any channel layout.
            // (Bug proven by CLI test: 0/156 with the fixed list, 156/156 here.)
            let rms: Float? = try? sampleBuffer.withAudioBufferList { list, _ in
                var sum: Float = 0
                var n = 0
                for buffer in list {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard count > 0 else { continue }
                    let samples = data.assumingMemoryBound(to: Float.self)
                    // Stride so even huge buffers cost ~256 multiplies per channel.
                    let step = max(1, count / 256)
                    var i = 0
                    while i < count { sum += samples[i] * samples[i]; n += 1; i += step }
                }
                return n > 0 ? sqrt(sum / Float(n)) : nil
            }
            guard let rms else { return }

            let now = CFAbsoluteTimeGetCurrent()
            if now - lastEmit >= 1.0 / 30.0 {
                lastEmit = now
                onRMS(rms)
            }
        }
    }
}
