import SwiftUI

/// The "Snippets" dashboard tab: a searchable library of reusable text. Click a
/// row (or its copy button) to put it on the clipboard.
struct SnippetsView: View {
    @ObservedObject private var store = SnippetStore.shared
    @State private var query = ""
    @State private var editing: Snippet?
    @State private var creating = false
    @State private var copiedID: UUID?

    private var results: [Snippet] { store.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.snippets.isEmpty {
                emptyState
            } else if results.isEmpty {
                noMatches
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(results) { row($0) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
        .sheet(item: $editing) { snip in
            SnippetEditor(snippet: snip) { store.upsert($0) }
        }
        .sheet(isPresented: $creating) {
            SnippetEditor(snippet: nil) { store.upsert($0) }
        }
    }

    // Toolbar only — the pane title lives in the big PaneHeader above.
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search snippets…", text: $query).textFieldStyle(.plain).frame(width: 180)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            Text("\(store.snippets.count)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Button { creating = true } label: { Label("New snippet", systemImage: "plus") }
                .controlSize(.small)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func row(_ s: Snippet) -> some View {
        HStack(spacing: 11) {
            EmblemChip(icon: "text.quote", tint: .purple)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.title.isEmpty ? "Untitled" : s.title)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if !s.keyword.isEmpty {
                        Text(s.keyword)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(Color.purple)
                    }
                }
                Text(s.content)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 10)
            Button { copy(s) } label: {
                Image(systemName: copiedID == s.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedID == s.id ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain).help("Copy to clipboard")
            Button { editing = s } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit")
            Button { store.remove(s.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete")
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .raisedCard()
        .contentShape(Rectangle())
        .onTapGesture { copy(s) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            GlassCircleBadge(icon: "text.quote")
            Text("No snippets yet").font(.system(size: 13, weight: .semibold))
            Text("Save text you paste often — signatures, addresses,\ncanned replies, code — and reuse it in one click.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { creating = true } label: { Label("Create your first snippet", systemImage: "plus") }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Spacer()
            GlassCircleBadge(icon: "magnifyingglass")
            Text("No snippets match “\(query)”").font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ s: Snippet) {
        store.copy(s)
        withAnimation(FlowMotion.bounce) { copiedID = s.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(FlowMotion.state) {
                if copiedID == s.id { copiedID = nil }
            }
        }
    }
}

/// Add/edit sheet for a single snippet.
private struct SnippetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Snippet
    private let isNew: Bool
    private let onSave: (Snippet) -> Void

    init(snippet: Snippet?, onSave: @escaping (Snippet) -> Void) {
        _draft = State(initialValue: snippet ?? Snippet(title: "", content: ""))
        isNew = snippet == nil
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("e.g. Work signature", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyword (optional)").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("e.g. ;sig", text: $draft.keyword)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Content").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $draft.content)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 150)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}
