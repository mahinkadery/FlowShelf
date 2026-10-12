import SwiftUI

struct NotchAudioCaptureSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    private let spectrum = AudioSpectrum.shared
    @State private var statusMessage = L10n.text("Audio capture is idle.")
    @State private var isStarting = false
    @State private var canRetry = false
    @State private var pendingMode = NotchAudioCaptureMode.compatibility
    @State private var confirmTap = false

    private var supportsTaps: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.text("Audio source"), selection: Binding(get: { settings.notchAudioCaptureMode }, set: { mode in
                guard mode != settings.notchAudioCaptureMode else { return }
                if mode == .compatibility { settings.notchAudioCaptureMode = mode }
                else { pendingMode = mode; confirmTap = true }
            })) {
                ForEach(NotchAudioCaptureMode.allCases) { mode in
                    Text(mode.label).tag(mode).disabled(mode != .compatibility && !supportsTaps)
                }
            }
            .disabled(!settings.notchEnabled || !settings.notchMediaEnabled || !settings.audioReactiveBars)
            Text(L10n.text("Experimental taps capture audio without a video stream. Audio is analyzed on this Mac for the bars, never saved or uploaded; the microphone is not used. macOS may ask for separate audio-recording permission and show its recording indicator."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L10n.text("Player-only mode matches the current player's audio processes. Browser/helper audio may be unavailable; it never falls back to other apps automatically. Compatibility remains the default."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                if isStarting { ProgressView().controlSize(.small) }
                Text(statusMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("Retry")) { spectrum.retry() }
                    .controlSize(.small).disabled(!canRetry)
            }
            Text(L10n.text("If capture is unavailable, the existing decorative bars are not a measurement of your music. Choose Compatibility to revert at any time."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(12).raisedCard()
        .onReceive(spectrum.$statusMessage.combineLatest(spectrum.$isStarting).receive(on: RunLoop.main)) { message, starting in
            statusMessage = message
            isStarting = starting
            canRetry = spectrum.canRetry
        }
        .alert(L10n.text("Enable experimental audio capture?"), isPresented: $confirmTap) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Use process tap")) { settings.notchAudioCaptureMode = pendingMode }
        } message: {
            Text(L10n.text("\(pendingMode.label)\n\nCapture runs while Notch media and audio-reactive bars are enabled and media is playing. macOS may request audio-recording access. No audio is saved, uploaded or muted. Locking or sleeping pauses capture."))
        }
    }
}
