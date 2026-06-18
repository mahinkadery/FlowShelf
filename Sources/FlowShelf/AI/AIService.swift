import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device text helpers backed by Apple's Foundation Models (the system LLM).
/// Everything runs locally — no network, no API key, no per-use cost. Available
/// only on Apple-Intelligence-capable Macs (Apple Silicon + macOS 26); on anything
/// older every call returns nil and `isSupported` is false, so callers hide the UI.
///
/// IMPORTANT (keeps the app lightweight): only call these from explicit user
/// actions. The model is loaded on demand by the OS and released after — never run
/// it in the background or on every clipboard capture.
enum AIService {

    /// Whether on-device generation is usable right now.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return modelAvailable() }
        #endif
        return false
    }

    /// A human-readable explanation of why AI is/ isn't available — surfaced in
    /// Settings so the user knows whether to enable Apple Intelligence, wait for a
    /// download, etc.
    static var statusMessage: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return statusMessage26() }
        #endif
        return "On-device AI needs macOS 26 or later."
    }

    static func title(for text: String) async -> String? {
        await run(instruction:
            "Write a short, specific title (3–6 words, no quotes, no trailing period) for the following text. Reply with only the title.",
            input: text, cap: 1200)
    }

    static func summarize(_ text: String) async -> String? {
        await run(instruction:
            "Summarize the following in 1–3 concise sentences. Reply with only the summary.",
            input: text, cap: 6000)
    }

    static func cleanUp(_ text: String) async -> String? {
        await run(instruction:
            "Clean up the following text: fix spacing, line breaks, and obvious typos, but keep the wording and meaning. Reply with only the cleaned text.",
            input: text, cap: 6000)
    }

    /// Free-form transform (Reply / Explain / Translate / custom prompt, etc.).
    static func transform(_ text: String, instruction: String) async -> String? {
        await run(instruction: instruction, input: text, cap: 6000)
    }

    /// A short digest of everything collected today.
    static func summarizeDay(_ texts: [String]) async -> String? {
        let joined = texts.enumerated()
            .map { "\($0.offset + 1). \($0.element.prefix(200))" }
            .joined(separator: "\n")
        return await run(instruction:
            "These are items the user collected today. Write a short, friendly digest (2–4 sentences) of what they were working on or saved. Reply with only the digest.",
            input: joined, cap: 8000)
    }

    /// AI-ranked search: returns the ids of items matching a natural-language
    /// query, most relevant first. Runs only when the user explicitly searches.
    static func smartSearch(query: String, candidates: [(id: String, text: String)]) async -> [String] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return await smartSearch26(query: query, candidates: candidates) }
        #endif
        return []
    }

    // MARK: - Implementation (availability-gated)

    private static func run(instruction: String, input: String, cap: Int) async -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clipped = String(trimmed.prefix(cap))
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await generate(instruction: instruction, input: clipped)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func modelAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @available(macOS 26.0, *)
    private static func statusMessage26() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Ready — runs entirely on your Mac."
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings ▸ Apple Intelligence & Siri, then reopen FlowShelf."
            case .modelNotReady:
                return "Apple Intelligence is still downloading its model. Try again in a few minutes."
            case .deviceNotEligible:
                return "This Mac isn’t eligible for Apple Intelligence."
            @unknown default:
                return "On-device AI is unavailable right now."
            }
        @unknown default:
            return "On-device AI is unavailable right now."
        }
    }

    @available(macOS 26.0, *)
    private static func smartSearch26(query: String, candidates: [(id: String, text: String)]) async -> [String] {
        guard case .available = SystemLanguageModel.default.availability else { return [] }
        let capped = Array(candidates.prefix(40))
        guard !capped.isEmpty else { return [] }
        let list = capped.enumerated()
            .map { "\($0.offset): \($0.element.text.replacingOccurrences(of: "\n", with: " ").prefix(120))" }
            .joined(separator: "\n")
        let prompt = """
        From the numbered list below, return the numbers of the items that best match this search: "\(query)".
        Reply with ONLY the matching numbers separated by commas (most relevant first), or "none".

        \(list)
        """
        guard let resp = try? await LanguageModelSession().respond(to: prompt) else { return [] }
        let nums = resp.content.components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .compactMap { Int($0) }
        return nums.compactMap { $0 >= 0 && $0 < capped.count ? capped[$0].id : nil }
    }

    @available(macOS 26.0, *)
    private static func generate(instruction: String, input: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: "\(instruction)\n\n\(input)")
            let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        } catch {
            NSLog("FlowShelf AI: generation failed: \(error)")
            return nil
        }
    }
    #endif
}
