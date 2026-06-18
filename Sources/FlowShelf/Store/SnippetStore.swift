import AppKit
import Combine

/// Source of truth for saved snippets. Small, local, persistent JSON next to the
/// shelf store. Owner-only file permissions since snippets can hold private text.
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published private(set) var snippets: [Snippet] = []

    private let dbURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport.appendingPathComponent("FlowShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        dbURL = baseDir.appendingPathComponent("snippets.json")
        load()
    }

    // MARK: - Mutations

    /// Insert a new snippet or replace an existing one (matched by id).
    func upsert(_ snippet: Snippet) {
        var s = snippet
        if s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.title = String(s.content.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let i = snippets.firstIndex(where: { $0.id == s.id }) {
            snippets[i] = s
        } else {
            snippets.insert(s, at: 0)
        }
        persist()
    }

    func remove(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    /// Copy a snippet's content to the clipboard and record the usage.
    func copy(_ snippet: Snippet) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet.content, forType: .string)
        if let i = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[i].useCount += 1
            snippets[i].lastUsed = Date()
            persist()
        }
    }

    func search(_ query: String) -> [Snippet] {
        guard !query.isEmpty else { return snippets }
        let q = query.lowercased()
        return snippets.filter {
            $0.title.lowercased().contains(q)
                || $0.content.lowercased().contains(q)
                || $0.keyword.lowercased().contains(q)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dbURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Snippet].self, from: data) {
            snippets = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: dbURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
        }
    }
}
