import AppKit

/// A gentle, occasional "buy me a coffee" nudge.
///
/// FlowShelf has no accounts or servers, so it can't *know* who donated — this is
/// honor-system: once the user taps "I already supported" (or opens the coffee
/// page), the prompt never shows again. It appears at most ~once a week, never in
/// the first few days, and only on a fraction of eligible launches so it feels
/// organic rather than mechanical.
@MainActor
final class SupporterPrompt {
    static let shared = SupporterPrompt()
    private let coffeeURL = URL(string: "https://buymeacoffee.com/mahinkadery")!
    private init() {}

    /// Call once at launch.
    func maybeShowAtLaunch() {
        let s = AppSettings.shared
        guard !s.hasSupported else { return }
        // Grace period: let new users enjoy it for a few days before any ask.
        guard Date().timeIntervalSince(s.firstLaunchAt) >= 3 * 24 * 3600 else { return }

        if let last = s.lastSupportPromptAt {
            // Later asks: at most once a week, and only ~60% of eligible launches
            // so it lands on a "random" day rather than clockwork.
            guard Date().timeIntervalSince(last) >= 7 * 24 * 3600 else { return }
            guard Double.random(in: 0...1) < 0.6 else { return }
        }
        // First-ever ask (last == nil) always shows once the grace period passes.

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.show()
        }
    }

    /// Show the prompt now (also used by a Settings "Support FlowShelf" button).
    func show(force: Bool = false) {
        let s = AppSettings.shared
        if !force, s.hasSupported { return }
        s.lastSupportPromptAt = Date()

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Enjoying FlowShelf? ☕️"
        alert.informativeText = """
        FlowShelf is free and built by one person in my spare time. If it's saved you \
        some clicks, a small coffee — $2.99, or $4.99 if you're feeling generous — helps \
        me keep building and shipping updates.

        No pressure, and I'll only ask once in a while.
        """
        alert.addButton(withTitle: "Buy me a coffee")       // .alertFirstButtonReturn
        alert.addButton(withTitle: "I already supported")   // .alertSecondButtonReturn
        alert.addButton(withTitle: "Maybe later")           // .alertThirdButtonReturn

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(coffeeURL)
            s.hasSupported = true   // engaged — don't nag again (honor system)
        case .alertSecondButtonReturn:
            s.hasSupported = true
        default:
            break                   // "Maybe later" — weekly timer already reset
        }
    }
}
