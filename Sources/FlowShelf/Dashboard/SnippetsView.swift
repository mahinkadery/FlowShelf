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
                    LazyVStack(spacing: 4) {
                        ForEach(results) { row($0) }
                    }
                    .padding(10)
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Snippets").font(.system(size: 15, weight: .semibold))
                Text("Reusable text — click to copy").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search…", text: $query).textFieldStyle(.plain).frame(width: 150)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            Button { creating = true } label: { Label("New", systemImage: "plus") }
                .controlSize(.small)
        }
        .padding(14)
    }

    private func row(_ s: Snippet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if !s.keyword.isEmpty {
                        Text(s.keyword)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(s.content)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
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
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture { copy(s) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "text.quote").font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("No snippets yet").font(.system(size: 13, weight: .medium))
            Text("Save text you paste often — signatures, addresses,\ncanned replies, code — and reuse it in one click.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { creating = true } label: { Label("Create your first snippet", systemImage: "plus") }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("No snippets match “\(query)”").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ s: Snippet) {
        store.copy(s)
        withAnimation(.easeOut(duration: 0.12)) { copiedID = s.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.2)) {
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
