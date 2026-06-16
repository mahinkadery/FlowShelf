import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CleanViewModel: ObservableObject {
    enum Phase {
        case idle
        case scanning(String)
        case results
        case removing
        case finished(trashed: Int, failed: Int)
    }

    @Published var phase: Phase = .idle
    @Published var result: AppScanResult?

    func scan(appURL: URL) {
        phase = .scanning(appURL.deletingPathExtension().lastPathComponent)
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                CleanerEngine.scan(appURL: appURL)
            }.value
            self.result = scanned
            self.phase = .results
        }
    }

    func toggle(_ id: UUID) {
        guard var r = result, let idx = r.items.firstIndex(where: { $0.id == id }) else { return }
        r.items[idx].selected.toggle()
        result = r
    }

    func setAll(_ selected: Bool, category: LeftoverCategory? = nil) {
        guard var r = result else { return }
        for i in r.items.indices where (category == nil || r.items[i].category == category) {
            r.items[i].selected = selected
        }
        result = r
    }

    func trashSelected() {
        guard let r = result else { return }
        phase = .removing
        Task {
            // If we're removing the app bundle itself, quit it first so the Trash
            // move doesn't fail or the app doesn't relaunch.
            if r.items.contains(where: { $0.selected && $0.category == .appBundle }) {
                await CleanerEngine.quitApp(bundleID: r.bundleID)
            }
            let urls = r.items.filter(\.selected).map(\.url)
            let outcome = CleanerEngine.moveToTrash(urls)
            // Drop a cleanup report onto the Shelf for 24h.
            ShelfStore.shared.add(ShelfItem(
                kind: .cleanReport,
                title: "Cleaned \(r.appName)",
                preview: "\(outcome.trashed) item(s) → Trash · \(formatBytes(r.selectedSize))",
                text: r.items.filter(\.selected).map(\.path).joined(separator: "\n"),
                sourceApp: "Cleaner"))
            phase = .finished(trashed: outcome.trashed, failed: outcome.failed.count)
        }
    }

    func reset() { result = nil; phase = .idle }
}

/// The "Clean" dashboard tab: drop an app → review leftovers → move to Trash.
struct CleanView: View {
    @StateObject private var model = CleanViewModel()
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch model.phase {
            case .idle:                 dropZone
            case .scanning(let name):   scanning(name)
            case .results:              results
            case .removing:             removing
            case .finished(let t, let f): finished(trashed: t, failed: f)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clean").font(.system(size: 15, weight: .semibold))
                Text("Uninstall an app and its leftover files")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.result != nil {
                Button("Start over") { model.reset() }.controlSize(.small)
            }
        }
        .padding(14)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 14) {
            Spacer()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 320, height: 180)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "trash.square")
                            .font(.system(size: 40))
                            .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                        Text("Drop an app here to uninstall")
                            .font(.system(size: 13, weight: .medium))
                        Text("or").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Choose App…") { chooseApp() }
                    }
                )
            Text("FlowShelf finds related files and moves them to the Trash —\nnothing is deleted permanently, and you can Put Back any time.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func scanning(_ name: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Scanning for \(name) leftovers…").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var removing: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Quitting the app and moving items to Trash…")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Results

    @ViewBuilder private var results: some View {
        if let r = model.result {
            VStack(spacing: 0) {
                summaryBar(r)
                Divider()
                if r.items.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "checkmark.seal").font(.system(size: 30)).foregroundStyle(.green)
                        Text("No leftover files found for \(r.appName).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(r.grouped(), id: \.0) { category, files in
                                categorySection(category, files)
                            }
                            Text("Tip: low-confidence matches are unchecked by default — review before trashing.")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        .padding(14)
                    }
                    Divider()
                    actionBar(r)
                }
            }
        }
    }

    private func summaryBar(_ r: AppScanResult) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: r.appURL.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.appName).font(.system(size: 13, weight: .semibold))
                Text("\(r.items.count) related items · \(formatBytes(r.totalSize)) total")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("All") { model.setAll(true) }
                Button("None") { model.setAll(false) }
            }.controlSize(.small)
        }
        .padding(12)
    }

    private func categorySection(_ category: LeftoverCategory, _ files: [LeftoverFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: category.symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(category.label).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(formatBytes(files.reduce(0) { $0 + $1.size }))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            ForEach(files) { file in
                fileRow(file)
            }
        }
    }

    private func fileRow(_ file: LeftoverFile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { file.selected },
                set: { _ in model.toggle(file.id) }))
                .labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName).font(.system(size: 12)).lineLimit(1)
                Text(file.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(file.confidence.label)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(file.confidence.color.opacity(0.18)))
                .foregroundStyle(file.confidence.color)
                .help(file.confidence.explanation)
            Text(formatBytes(file.size)).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }

    private func actionBar(_ r: AppScanResult) -> some View {
        HStack {
            Text("\(r.selectedCount) selected · \(formatBytes(r.selectedSize))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button {
                model.trashSelected()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(r.selectedCount == 0)
        }
        .padding(12)
    }

    private func finished(trashed: Int, failed: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
            Text("Moved \(trashed) item(s) to Trash")
                .font(.system(size: 14, weight: .semibold))
            if failed > 0 {
                Text("\(failed) couldn’t be removed (may need admin rights).")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text("You can restore anything from the Trash with “Put Back”.\nA cleanup report was added to your Shelf.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Open Trash") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                }
                Button("Clean another") { model.reset() }
            }.padding(.top, 4)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Drop / choose

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "app" else { return }
            Task { @MainActor in model.scan(appURL: url) }
        }
        return true
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.scan(appURL: url)
        }
    }
}
