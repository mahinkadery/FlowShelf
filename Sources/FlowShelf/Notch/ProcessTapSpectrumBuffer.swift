import AudioToolbox
import Accelerate
import Foundation

final class ProcessTapSpectrumBuffer: @unchecked Sendable {
    static let frameCount = 2048
    private let lock = NSLock()
    private var samples = [Float](repeating: 0, count: frameCount * 2)
    private var position = 0
    private var populated = 0
    private var revision: UInt64 = 0
    private var consumedRevision: UInt64 = 0
    let format: AudioStreamBasicDescription

    init?(format: AudioStreamBasicDescription) {
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32,
              (1...2).contains(format.mChannelsPerFrame),
              format.mBytesPerFrame == 4 * (planar ? 1 : format.mChannelsPerFrame),
              format.mSampleRate.isFinite, (8_000...192_000).contains(format.mSampleRate) else { return nil }
        self.format = format
    }

    func append(_ input: UnsafePointer<AudioBufferList>) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let channels = Int(format.mChannelsPerFrame)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard buffers.count == (planar ? channels : 1) else { return }
        var frames = Int.max
        for buffer in buffers {
            guard buffer.mData != nil, buffer.mNumberChannels == (planar ? 1 : UInt32(channels)) else { return }
            frames = min(frames, Int(buffer.mDataByteSize) / (4 * (planar ? 1 : channels)))
        }
        guard frames > 0 else { return }
        let firstFrame = max(0, frames - Self.frameCount)
        for frame in firstFrame..<frames {
            for channel in 0..<channels {
                let buffer = buffers[planar ? channel : 0]
                let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                let value = pointer[planar ? frame : frame * channels + channel]
                samples[channel * Self.frameCount + position] = value.isFinite ? max(-1, min(1, value)) : 0
            }
            position = (position + 1) % Self.frameCount
        }
        populated = min(Self.frameCount, populated + frames - firstFrame)
        revision &+= 1
    }

    func takeWindow() -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard populated == Self.frameCount, revision != consumedRevision else { return nil }
        consumedRevision = revision
        var window = [Float](repeating: 0, count: Self.frameCount * Int(format.mChannelsPerFrame))
        for channel in 0..<Int(format.mChannelsPerFrame) {
            for frame in 0..<Self.frameCount {
                window[channel * Self.frameCount + frame] = samples[channel * Self.frameCount + (position + frame) % Self.frameCount]
            }
        }
        return window
    }
}

final class ProcessTapSpectrumAnalyzer {
    private let setup: FFTSetup
    private let count = ProcessTapSpectrumBuffer.frameCount
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: ProcessTapSpectrumBuffer.frameCount, isHalfWindow: false)
    private var windowed = [Float](repeating: 0, count: 2048)
    private var real = [Float](repeating: 0, count: 1024)
    private var imaginary = [Float](repeating: 0, count: 1024)
    private var powers = [Float](repeating: 0, count: 1024)

    init?() {
        guard let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func analyze(_ samples: [Float], sampleRate: Float, channels: Int) -> (Float, [Float])? {
        guard (1...2).contains(channels), samples.count == count * channels,
              sampleRate.isFinite, sampleRate >= 8_000 else { return nil }
        var energy: Float = 0
        var bands = [Float](repeating: 0, count: 6)
        let ranges: [(Float, Float)] = [(45, 140), (140, 320), (320, 800), (800, 2_200), (2_200, 5_200), (5_200, 16_000)]
        samples.withUnsafeBufferPointer { pointer in
            for channel in 0..<channels {
                let channelSamples = pointer.baseAddress!.advanced(by: channel * count)
                var squareSum: Float = 0
                vDSP_svesq(channelSamples, 1, &squareSum, vDSP_Length(count))
                energy += squareSum
                vDSP_vmul(channelSamples, 1, window, 1, &windowed, 1, vDSP_Length(count))
                real.withUnsafeMutableBufferPointer { realPointer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                        var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                        windowed.withUnsafeBytes { bytes in
                            vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, 1024)
                        }
                        vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(kFFTDirection_Forward))
                        vDSP_zvmags(&split, 1, &powers, 1, 1024)
                    }
                }
                let binWidth = sampleRate / Float(count)
                for (index, range) in ranges.enumerated() {
                    let first = max(1, Int(ceil(range.0 / binWidth)))
                    let last = min(1023, Int(floor(range.1 / binWidth)))
                    guard first <= last else { continue }
                    for bin in first...last { bands[index] += powers[bin] / Float(last - first + 1) }
                }
            }
        }
        return (sqrt(energy / Float(count * channels)), bands.map { sqrt($0 / Float(channels)) })
    }
}
