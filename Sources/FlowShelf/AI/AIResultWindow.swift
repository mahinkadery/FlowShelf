import AppKit
import SwiftUI

/// A small, plain window that shows what an on-device AI action produced
/// (Summarize, Ask AI, Summarize day, …). Results no longer get dumped onto the
/// shelf automatically — you see them here and choose to Copy or Add to Shelf.
@MainActor
final class AIResultPresenter {
    static let shared = AIResultPresenter()
    private var window: NSWindow?
    private let model = AIResultModel()

    private init() {}

    /// Show the window with a spinner, run the work, then fill in the result.
    func present(title: String, _ work: @escaping () async -> String?) {
        model.title = title
        model.state = .loading
        show()
        Task {
            let out = await work()
            if let out, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.state = .text(out)
            } else {
                model.state = .failed
            }
        }
    }

    private func show() {
        if window == nil {
            let host = NSHostingController(rootView: AIResultView(model: model) { [weak self] in
                self?.window?.close()
            })
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.level = .floating
            window = w
            w.center()   // only on first creation — don't yank a window the user moved
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AIResultModel: ObservableObject {
    enum State { case loading, text(String), failed }
    @Published var title = ""
    @Published var state: State = .loading
}

private struct AIResultView: View {
    @ObservedObject var model: AIResultModel
    var onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor).font(.system(size: 12))
                Text(model.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            Divider()

            Group {
                switch model.state {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .text(let t):
                    ScrollView {
                        Text(t).font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .failed:
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 22)).foregroundStyle(.secondary)
                        Text("Couldn't get a result.\nMake sure Apple Intelligence is enabled.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack(spacing: 8) {
                if case .text(let t) = model.state {
                    Button { copy(t) } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button { addToShelf(t) } label: {
                        Label("Add to Shelf", systemImage: "tray.and.arrow.down")
                    }
                }
                Spacer()
                Button("Close") { onClose() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 400, height: 320)
    }

    private func copy(_ text: String) {
        AppSettings.shared.ignoreNextCopy = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { withAnimation { copied = false } }
    }

    private func addToShelf(_ text: String) {
        ShelfStore.shared.add(ShelfItem(kind: .text, title: model.title,
            preview: text.firstLine(max: 140), text: text, sourceApp: "AI"))
        onClose()
    }
}
