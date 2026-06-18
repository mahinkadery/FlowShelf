import Foundation

/// A reusable piece of text — an email signature, an address, a code block, a
/// canned reply. Lives forever (unlike a Shelf item), is searchable, and is one
/// click away from the clipboard.
struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    /// Optional shorthand the user types to find it, e.g. ";addr". Display-only
    /// for now (a future opt-in keystroke watcher can auto-expand it).
    var keyword: String
    var createdAt: Date
    var lastUsed: Date?
    var useCount: Int

    init(id: UUID = UUID(), title: String, content: String, keyword: String = "",
         createdAt: Date = Date(), lastUsed: Date? = nil, useCount: Int = 0) {
        self.id = id
        self.title = title
        self.content = content
        self.keyword = keyword
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}
