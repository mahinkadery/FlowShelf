import SwiftUI

/// One compact row in the menu-bar list. Keyboard-first, mouse optional.
struct ShelfItemRow: View {
    let item: ShelfItem
    var selected: Bool = false
    @ObservedObject private var store = ShelfStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? item.kind.label : item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            if hovering {
                rowActions
            } else {
                // Recompute the label periodically so it counts down while visible.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(expiryText)
                        .font(.system(size: 10))
                        .foregroundStyle(expiryColor)
                }
                .help(expiryHelp)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18)
                      : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag { DragDrop.provider(for: item) }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var leading: some View {
        if let thumb = store.thumbnail(for: item), item.hasImage {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var keepForever: Bool { AppSettings.shared.clipboardRetention.isForever }

    /// AI actions only for text-bearing items, and only when supported + enabled.
    private var showsAI: Bool {
        guard AppSettings.shared.aiEnabled, AIService.isSupported else { return false }
        switch item.kind {
        case .text, .ocr, .link, .cleanReport: return (item.text?.isEmpty == false) || !item.preview.isEmpty
        default: return false
        }
    }

    /// In Permanent mode items never expire, so show "Saved" rather than a
    /// misleading countdown.
    private var expiryText: String {
        if item.pinned { return "Pinned" }
        return keepForever ? "Saved" : item.expiryLabel
    }
    private var expiryColor: Color {
        if item.pinned { return .orange }
        if keepForever { return .secondary.opacity(0.7) }
        return item.expiringSoon ? .red : .secondary.opacity(0.7)
    }
    private var expiryHelp: String {
        if item.pinned { return "Pinned — won’t auto-delete" }
        if keepForever { return "Saved — permanent retention is on" }
        return "Auto-deletes \(item.expiresAt.shortTime)"
    }

    private var subtitle: String {
        var parts: [String] = [item.kind.label]
        if let app = item.sourceApp, !app.isEmpty { parts.append(app) }
        if item.kind == .text || item.kind == .ocr || item.kind == .link {
            return item.preview
        }
        return parts.joined(separator: " · ")
    }

    private var rowActions: some View {
        HStack(spacing: 8) {
            iconButton("doc.on.doc", "Copy") { ItemActions.copyToPasteboard(item) }
            iconButton(item.pinned ? "pin.slash" : "pin", item.pinned ? "Unpin" : "Pin") {
                store.togglePin(item.id)
            }
            iconButton("xmark", "Remove") { store.remove(item.id) }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Copy") { ItemActions.copyToPasteboard(item) }
        if item.kind == .link || item.kind == .file || item.hasImage {
            Button("Open") { ItemActions.open(item) }
        }
        if item.kind == .file || item.hasImage {
            Button("Reveal in Finder") { ItemActions.reveal(item) }
        }
        if item.hasImage {
            Button("Annotate…") { ItemActions.annotate(item) }
            Button("Run OCR") { ItemActions.runOCR(item) }
        }
        if showsAI {
            Divider()
            Button("Summarize (AI)") { ItemActions.aiSummarize(item) }
            Button("Clean up (AI)") { ItemActions.aiCleanUp(item) }
            Button("Smart title (AI)") { ItemActions.aiTitle(item) }
            Menu("Ask AI") {
                Button("Reply") { ItemActions.aiTransform(item, instruction: "Write a concise reply to the following message. Reply with only the reply.", title: "AI reply") }
                Button("Explain") { ItemActions.aiTransform(item, instruction: "Explain the following clearly and simply. Reply with only the explanation.", title: "Explanation") }
                Button("Make formal") { ItemActions.aiTransform(item, instruction: "Rewrite the following in a formal, professional tone. Reply with only the rewrite.", title: "Formal") }
                Button("Make casual") { ItemActions.aiTransform(item, instruction: "Rewrite the following in a casual, friendly tone. Reply with only the rewrite.", title: "Casual") }
                Button("Bullet points") { ItemActions.aiTransform(item, instruction: "Turn the following into concise bullet points. Reply with only the bullet points.", title: "Bullets") }
                Button("Translate…") { ItemActions.aiTranslate(item) }
                Divider()
                Button("Custom…") { ItemActions.aiAsk(item) }
            }
        }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item.id) }
        Button("Remove", role: .destructive) { store.remove(item.id) }
    }
}
