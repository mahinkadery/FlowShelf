import AppKit

/// Semantic trackpad haptics. Free polish on Force Touch trackpads; silently a
/// no-op everywhere else. Call sites name the *event*, not the waveform, so the
/// mapping can be tuned in one place.
enum Haptics {
    /// An item landed somewhere (shelf, notch, pin board).
    static func drop() { perform(.generic) }

    /// Something was copied to the clipboard.
    static func copy() { perform(.levelChange) }

    /// An item was removed or cleared.
    static func delete() { perform(.generic) }

    /// A pin/favorite toggled.
    static func pin() { perform(.levelChange) }

    /// A window snapped into place / an edge was hit.
    static func snap() { perform(.alignment) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
