import Foundation

enum ShelfRetrieval {
    struct Candidate: Sendable {
        let id: String
        let text: String
    }

    private static let ignoredWords: Set<String> = [
        "a", "an", "and", "are", "about", "can", "could", "did", "do", "does",
        "find", "for", "from", "have", "how", "i", "in", "is", "it", "me", "my",
        "of", "on", "please", "saved", "search", "shelf", "show", "that", "the",
        "these", "this", "to", "was", "what", "when", "where", "which", "with"
    ]

    static func terms(_ query: String) -> [String] {
        Array(Set(fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { !ignoredWords.contains($0) })).sorted()
    }

    static func rank(query: String, candidates: [Candidate], limit: Int,
                     includeUnmatched: Bool = false) -> [Candidate] {
        guard limit > 0 else { return [] }
        let keywords = terms(query)
        let ranked = candidates.enumerated().map { position, candidate in
            let haystack = fold(candidate.text)
            let score = keywords.reduce(0) { total, word in
                total + (haystack.contains(word) ? 1 : 0)
            }
            return (position: position, candidate: candidate, score: score)
        }
        return ranked.filter { includeUnmatched || $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.position < $1.position
            }
            .prefix(limit).map(\.candidate)
    }

    static func excerpt(_ text: String, query: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        let ranges = terms(query).compactMap {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
        }
        let match = ranges.map(\.lowerBound).min() ?? text.startIndex
        let start = text.index(match, offsetBy: -min(100, limit / 4), limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end]
            + (end == text.endIndex ? "" : "…")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct AIContextItem: Identifiable, Sendable {
    enum Kind: Sendable { case shelf, snippet }
    let id: UUID
    let kind: Kind
    let title: String
    let text: String
}

struct ShelfAnswer {
    let text: String
    let sources: [AIContextItem]
}
