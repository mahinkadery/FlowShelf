import AppKit
import Combine

/// Current now-playing snapshot, aggregated from the adapter's diff stream.
struct NowPlaying: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    var duration: Double = 0
    var elapsed: Double = 0
    var bundleID = ""
    var artwork: NSImage?

    var hasMedia: Bool { !title.isEmpty }
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
    private var stdoutBuffer = Data()
    private var running = false
    private var lastArtHash = 0

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

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consume(chunk) }
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
        if let s = stream, s.isRunning { s.terminate() }
        stream = nil
        stdoutBuffer.removeAll()
        now = NowPlaying()
    }

    /// Restart if the stream dies (it can, e.g. on the machine waking) while the
    /// feature is still meant to be on.
    private func handleExit() {
        guard running else { return }
        running = false
        stream = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, AppSettings.shared.notchMediaEnabled else { return }
            self.start()
        }
    }

    // MARK: Controls (raw MRCommand values via the adapter's `send`)

    func togglePlayPause() { send(2) }
    func next() { send(4) }
    func previous() { send(5) }

    private func send(_ command: Int) {
        guard let script = scriptPath, let fw = frameworkPath else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script, fw, "send", String(command)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: Parsing the diff stream

    private func consume(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        // Process complete, newline-terminated JSON records.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            apply(line)
        }
    }

    private func apply(_ line: Data) {
        // Each record is an envelope: {"type":"data","diff":Bool,"payload":{…}}.
        // We merge payloads into the running state; an empty payload = no media.
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (obj["type"] as? String) == "data",
              let payload = obj["payload"] as? [String: Any] else { return }

        if payload.isEmpty {
            if now != NowPlaying() { now = NowPlaying(); lastArtHash = 0; Self.crumb("cleared") }
            return
        }

        var next = now
        if let v = payload["title"] as? String {
            if v != next.title { next.artwork = nil; lastArtHash = 0 }   // new track → drop stale art
            next.title = v
        }
        if let v = payload["artist"] as? String { next.artist = v }
        if let v = payload["album"] as? String { next.album = v }
        if let v = payload["playing"] as? Bool { next.isPlaying = v }
        if let v = payload["duration"] as? Double { next.duration = v }
        if let v = payload["elapsedTime"] as? Double { next.elapsed = v }
        if let v = payload["bundleIdentifier"] as? String { next.bundleID = v }

        // Artwork is re-sent only on track change; decode only when it changes.
        if let b64 = payload["artworkData"] as? String {
            let h = b64.hashValue
            if h != lastArtHash {
                lastArtHash = h
                next.artwork = Data(base64Encoded: b64).flatMap { NSImage(data: $0) }
            }
        }
        if next.title.isEmpty { next = NowPlaying(); lastArtHash = 0 }

        if next != now {
            now = next
            Self.crumb("now: '\(next.title)' — '\(next.artist)' playing=\(next.isPlaying) art=\(next.artwork != nil)")
        }
    }
}
