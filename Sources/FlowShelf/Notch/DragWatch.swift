import AppKit

/// Detects a file/text drag *starting anywhere on screen* — no permissions needed.
///
/// macOS puts every drag session's payload on the shared drag pasteboard, so a
/// change in its `changeCount` while a mouse button is down means a drag just
/// began. Polling this (rather than a global event monitor) works without
/// Accessibility access. ~100ms cadence; the check is a couple of cheap reads
/// when idle.
@MainActor
final class DragWatch {
    static let shared = DragWatch()

    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private(set) var isDragging = false
    private var timer: Timer?
    private var lastChangeCount = 0

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard(name: .drag).changeCount
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.04
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isDragging { isDragging = false; onDragEnded?() }
    }

    private func tick() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        if isDragging {
            // Drag ends when the button is released.
            if !mouseDown {
                isDragging = false
                onDragEnded?()
            }
            return
        }

        // Idle fast-path: nothing to do until a button is held.
        guard mouseDown else { return }

        let pb = NSPasteboard(name: .drag)
        let count = pb.changeCount
        if count != lastChangeCount {
            lastChangeCount = count
            if (pb.types?.count ?? 0) > 0 {
                isDragging = true
                onDragBegan?()
            }
        }
    }
}
