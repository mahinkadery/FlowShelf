import AppKit

/// Detects a quick mouse "shake" (rapid left-right wiggles) — Dropover's signature
/// gesture — and fires `onShake`. Uses a global mouse monitor (no Accessibility
/// needed for mouse-move events).
@MainActor
final class ShakeDetector {
    static let shared = ShakeDetector()

    var onShake: (() -> Void)?
    private(set) var isRunning = false

    private var monitor: Any?
    private var lastX: CGFloat = 0
    private var lastDirection = 0          // -1, 0, +1
    private var reversals: [Date] = []
    private var lastTrigger = Date.distantPast

    // Tuning: how many direction flips, how fast, and the cooldown.
    private let minStep: CGFloat = 6
    private let window: TimeInterval = 0.6
    private let neededReversals = 4
    private let cooldown: TimeInterval = 1.2

    private init() {}

    func start() {
        guard monitor == nil else { return }
        isRunning = true
        lastX = NSEvent.mouseLocation.x
        lastDirection = 0
        reversals.removeAll()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.handleMove() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRunning = false
        reversals.removeAll()
    }

    private func handleMove() {
        let x = NSEvent.mouseLocation.x
        let dx = x - lastX
        lastX = x
        guard abs(dx) > minStep else { return }

        let direction = dx > 0 ? 1 : -1
        if lastDirection != 0, direction != lastDirection {
            let now = Date()
            reversals.append(now)
            reversals = reversals.filter { now.timeIntervalSince($0) < window }
            if reversals.count >= neededReversals,
               now.timeIntervalSince(lastTrigger) > cooldown {
                lastTrigger = now
                reversals.removeAll()
                onShake?()
            }
        }
        lastDirection = direction
    }
}
