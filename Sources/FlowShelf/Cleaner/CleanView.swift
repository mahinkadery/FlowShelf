import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CleanViewModel: ObservableObject {
    enum Phase {
        case idle
        case scanning(String)
        case results
        case removing
        case finished(trashed: Int, failed: [URL])
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
        guard !CleanerEngine.isProtected(r.items[idx].url) else { return }   // can't be removed anyway
        r.items[idx].selected.toggle()
        result = r
    }

    func setAll(_ selected: Bool, category: LeftoverCategory? = nil) {
        guard var r = result else { return }
        for i in r.items.indices where (category == nil || r.items[i].category == category) {
            if selected && CleanerEngine.isProtected(r.items[i].url) { continue }
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
            // Drop a cleanup report onto the Shelf for 24h — including any files we
            // couldn't remove, so the user can find and delete them later.
            var reportText = outcome.trashed > 0
                ? "Trashed:\n" + urls.filter { !outcome.failed.contains($0) }.map(\.path).joined(separator: "\n")
                : ""
            if !outcome.failed.isEmpty {
                reportText += "\n\nCouldn’t remove (\(outcome.failed.count)):\n"
                    + outcome.failed.map(\.path).joined(separator: "\n")
            }
            ShelfStore.shared.add(ShelfItem(
                kind: .cleanReport,
                title: "Cleaned \(r.appName)",
                preview: "\(outcome.trashed) item(s) → Trash"
                    + (outcome.failed.isEmpty ? "" : " · \(outcome.failed.count) left")
                    + " · \(formatBytes(r.selectedSize))",
                text: reportText.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceApp: "Cleaner"))
            phase = .finished(trashed: outcome.trashed, failed: outcome.failed)
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
                if CleanerEngine.isProtected(r.appURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.purple)
                        Text("\(r.appName) is a built-in macOS app. Built-in apps live on the protected system volume and can’t be uninstalled — only their leftover files (if any) can be removed.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.purple.opacity(0.08))
                }
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
        let locked = CleanerEngine.isProtected(file.url)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { file.selected },
                set: { _ in model.toggle(file.id) }))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(locked)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName).font(.system(size: 12)).lineLimit(1)
                Text(file.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if locked {
                Text("Protected")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    .foregroundStyle(.secondary)
                    .help("Built-in macOS item on the protected system volume — can't be removed by any app.")
            } else {
                Text(file.confidence.label)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(file.confidence.color.opacity(0.18)))
                    .foregroundStyle(file.confidence.color)
                    .help(file.confidence.explanation)
            }
            Text(formatBytes(file.size)).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
        }
        .padding(.vertical, 2)
        .opacity(locked ? 0.55 : 1)
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

    private func finished(trashed: Int, failed: [URL]) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(failed.isEmpty ? .green : .orange)
                Text("Moved \(trashed) item(s) to Trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Trashed items can be restored with “Put Back”. A cleanup report was added to your Shelf.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18).padding(.horizontal, 20).padding(.bottom, 12)

            if !failed.isEmpty {
                Divider()
                failedSection(failed)
            }

            Divider()
            HStack {
                Button("Open Trash") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                }
                Spacer()
                Button("Clean another") { model.reset() }
            }.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Lists the files FlowShelf couldn't move to Trash so the user can find and
    /// remove them by hand. Items under ~/Library need Full Disk Access; system
    /// items under /Library need an admin account.
    private func failedSection(_ failed: [URL]) -> some View {
        let needsFDA = failed.contains { $0.path.hasPrefix(homePath) }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(failed.count) couldn’t be removed")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text("Reveal each one in Finder and delete it manually. Library items need Full Disk Access; system items need an admin. Built-in macOS items can’t be removed at all.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(failed, id: \.self) { url in failedRow(url) }
                }
                .padding(.horizontal, 14).padding(.bottom, 6)
            }
            .frame(maxHeight: 220)

            HStack(spacing: 8) {
                if needsFDA {
                    Button { Permissions.openSettings(.fullDiskAccess) } label: {
                        Label("Grant Full Disk Access", systemImage: "lock.open")
                    }
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting(failed) } label: {
                    Label("Reveal all", systemImage: "magnifyingglass")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failed.map(\.path).joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy paths", systemImage: "doc.on.doc")
                }
                Spacer()
            }
            .controlSize(.small)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func failedRow(_ url: URL) -> some View {
        let reason = failReason(url)
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                Text(url.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(reason.label)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(reason.color.opacity(0.18)))
                .foregroundStyle(reason.color)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }

    private var homePath: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private func failReason(_ url: URL) -> (label: String, color: Color) {
        if CleanerEngine.isProtected(url) { return ("Protected by macOS", .purple) }
        return url.path.hasPrefix(homePath)
            ? ("Needs Full Disk Access", .orange)
            : ("Needs admin", .red)
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
