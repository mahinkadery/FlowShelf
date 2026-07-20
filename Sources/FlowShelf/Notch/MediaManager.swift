import AppKit
import Combine
import CoreImage

/// Current now-playing snapshot, aggregated from the adapter's diff stream.
struct NowPlaying: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    var duration: Double = 0
    var elapsed: Double = 0
    /// When `elapsed` was last reported — playback position is extrapolated from
    /// here while playing (the adapter only sends diffs on state changes).
    var elapsedAt = Date.distantPast
    var bundleID = ""
    var artwork: NSImage?
    /// Dominant artwork color (computed off-main with the artwork) — tints the
    /// live-activity audio bars so they glow in the media's own color.
    var accent: NSColor?

    var hasMedia: Bool { !title.isEmpty }

    /// Best-estimate current position, extrapolated while playing.
    var currentPosition: Double {
        guard isPlaying, elapsedAt != .distantPast else { return elapsed }
        let pos = elapsed + Date().timeIntervalSince(elapsedAt)
        return duration > 0 ? min(pos, duration) : pos
    }
}

/// Reads system-wide "Now Playing" media (any app — Music, Spotify, browsers) on
/// macOS via `mediaremote-adapter` (BSD-3, Jonas van den Berg). Apple blocked the
/// private MediaRemote framework for in-process reads in macOS 15.4, so the
/// adapter runs it out-of-process through a `/usr/bin/perl` bridge and streams
/// JSON diffs on stdout. Playback commands still work via the adapter's `send`.
///
/// Vendored under `Vendor/mediaremote-adapter/`; bundled as
/// `Contents/Frameworks/MediaRemoteAdapter.framework` + `Resources/mediaremote-adapter.pl`.
@MainActor
final class MediaManager: ObservableObject {
    static let shared = MediaManager()

    @Published private(set) var now = NowPlaying()

    private var stream: Process?
    private var running = false

    private init() {}

    // Debug (env FLOWSHELF_MEDIA_DEBUG=1): trace to /tmp/flowshelf-media.log.
    private static let dbg = ProcessInfo.processInfo.environment["FLOWSHELF_MEDIA_DEBUG"] == "1"
    private static func crumb(_ s: String) {
        guard dbg else { return }
        let line = "[\(Date().timeIntervalSince1970)] \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/flowshelf-media.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: Paths to the vendored adapter

    private var scriptPath: String? {
        Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl")
    }
    private var frameworkPath: String? {
        guard let fw = Bundle.main.privateFrameworksPath else { return nil }
        return fw + "/MediaRemoteAdapter.framework"
    }
    /// The feature can run at all only if both vendored pieces are present.
    var isAvailable: Bool { scriptPath != nil && frameworkPath != nil }

    // MARK: Lifecycle

    func start() {
        guard !running, let script = scriptPath, let fw = frameworkPath,
              FileManager.default.fileExists(atPath: fw) else { return }
        running = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // `stream` emits a JSON diff whenever the now-playing state changes, and a
        // literal `null` when playback stops. Debounce coalesces rapid updates.
        proc.arguments = [script, fw, "stream", "--debounce=200"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice

        // Fresh parser per stream; it lives entirely on the pipe's reader thread
        // (JSON + artwork decode happen there, NOT on the main actor).
        let parser = StreamParser()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            parser.consume(chunk) { update in
                Task { @MainActor in self?.apply(update) }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.handleExit() }
        }
        Self.crumb("start script=\(script) fwExists=\(FileManager.default.fileExists(atPath: fw))")
        do {
            try proc.run()
            stream = proc
        } catch {
            NSLog("MediaManager: failed to start adapter: \(error)")
            running = false
        }
    }

    func stop() {
        running = false
        stream?.terminationHandler = nil
        (stream?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if let s = stream, s.isRunning { s.terminate() }
        stream = nil
        now = NowPlaying()
        AudioSpectrum.shared.setActive(false)
    }

    /// Restart if the stream dies (it can, e.g. on the machine waking) while the
    /// feature is still meant to be on.
    private func handleExit() {
        guard running else { return }
        running = false
        stream = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self,
                  AppSettings.shared.notchEnabled,
                  AppSettings.shared.notchMediaEnabled else { return }
            self.start()
        }
    }

    // MARK: Controls (raw MRCommand values via the adapter's `send`)

    func togglePlayPause() { send(2) }
    func next() { send(4) }
    func previous() { send(5) }

    /// Seek to an absolute position. Optimistically updates the local state so
    /// the progress bar lands where the user pointed without waiting for a diff.
    func seek(to seconds: Double) {
        guard let script = scriptPath, let fw = frameworkPath else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script, fw, "seek", String(Int(seconds * 1_000_000))]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        now.elapsed = seconds
        now.elapsedAt = Date()
    }

    private func send(_ command: Int) {
        guard let script = scriptPath, let fw = frameworkPath else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script, fw, "send", String(command)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: Applying parsed updates (main actor — merge + publish only)

    private func apply(_ up: StreamParser.Update) {
        // An empty payload = no media (the adapter's `null`).
        if up.payload.isEmpty {
            if now != NowPlaying() { now = NowPlaying(); Self.crumb("cleared") }
            AudioSpectrum.shared.setActive(false)
            return
        }

        var next = now
        if let v = up.payload["title"] as? String {
            if v != next.title, !up.artworkChanged { next.artwork = nil }  // new track → drop stale art
            next.title = v
        }
        if let v = up.payload["artist"] as? String { next.artist = v }
        if let v = up.payload["album"] as? String { next.album = v }
        if let v = up.payload["playing"] as? Bool { next.isPlaying = v }
        if let v = up.payload["duration"] as? Double { next.duration = v }
        if let v = up.payload["elapsedTime"] as? Double { next.elapsed = v; next.elapsedAt = Date() }
        if let v = up.payload["bundleIdentifier"] as? String { next.bundleID = v }
        if up.artworkChanged { next.artwork = up.artwork; next.accent = up.accent }
        if next.title.isEmpty { next = NowPlaying() }

        if next != now {
            now = next
            // Tap system audio for the reactive bars only while music plays.
            AudioSpectrum.shared.setActive(
                AppSettings.shared.notchEnabled &&
                AppSettings.shared.notchMediaEnabled &&
                next.hasMedia && next.isPlaying &&
                AppSettings.shared.audioReactiveBars
            )
            Self.crumb("now: '\(next.title)' — '\(next.artist)' playing=\(next.isPlaying) art=\(next.artwork != nil)")
        }
    }
}

/// Line-buffers the adapter's stdout and does ALL the heavy lifting — JSON
/// parsing and base64 → NSImage artwork decoding — on the pipe's reader thread,
/// so track changes never hitch the UI. One instance per stream; only ever
/// touched from that stream's readability handler.
private final class StreamParser {
    struct Update {
        var payload: [String: Any]
        var artwork: NSImage?
        var accent: NSColor?
        var artworkChanged: Bool
    }

    private var buffer = Data()
    private var lastArtHash = 0
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    func consume(_ chunk: Data, emit: (Update) -> Void) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  (obj["type"] as? String) == "data",
                  let payload = obj["payload"] as? [String: Any] else { continue }

            // Artwork is re-sent only on change; decode (and pull its dominant
            // color) only then — both are expensive and both stay off-main.
            var artwork: NSImage?
            var accent: NSColor?
            var artworkChanged = false
            if let b64 = payload["artworkData"] as? String {
                let h = b64.hashValue
                if h != lastArtHash {
                    lastArtHash = h
                    if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                        artwork = img
                        accent = averageColor(of: data)
                    }
                    artworkChanged = true
                }
            }
            emit(Update(payload: payload, artwork: artwork, accent: accent, artworkChanged: artworkChanged))
        }
    }

    /// Average color of the artwork via CIAreaAverage (GPU, one pixel out).
    private func averageColor(of data: Data) -> NSColor? {
        guard let ci = CIImage(data: data) else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        guard px[3] > 0 else { return nil }
        return NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                       blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}
