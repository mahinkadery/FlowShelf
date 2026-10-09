import SwiftUI
import AppKit

struct BatchDragHandle: NSViewRepresentable {
    var count: Int
    var prepare: () throws -> [ShelfBatchTransfer.Entry]
    var report: (String) -> Void

    func makeNSView(context: Context) -> BatchDragView { BatchDragView() }

    func updateNSView(_ view: BatchDragView, context: Context) {
        view.count = count
        view.prepare = prepare
        view.report = report
        view.toolTip = "Drag selected items. Originals stay in place; the receiving app decides which types it accepts."
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("Drag \(count) selected items")
        view.needsDisplay = true
    }
}

final class BatchDragView: NSView, NSDraggingSource {
    var count = 0
    var prepare: (() throws -> [ShelfBatchTransfer.Entry])?
    var report: ((String) -> Void)?
    private var initialEvent: NSEvent?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(count > 0 ? 0.15 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let label = NSAttributedString(string: "⠿ Drag \(count) items", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: count > 0 ? NSColor.labelColor : NSColor.disabledControlTextColor
        ])
        label.draw(at: NSPoint(x: (bounds.width - label.size().width) / 2,
                               y: (bounds.height - label.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) { initialEvent = event }
    override func mouseUp(with event: NSEvent) { initialEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard count > 0, let initialEvent, let prepare,
              hypot(event.locationInWindow.x - initialEvent.locationInWindow.x,
                    event.locationInWindow.y - initialEvent.locationInWindow.y) >= 4 else { return }
        self.initialEvent = nil
        do {
            let entries = try prepare()
            guard !entries.isEmpty else { return }
            let origin = convert(event.locationInWindow, from: nil)
            let draggingItems = entries.enumerated().map { index, entry in
                let draggingItem = NSDraggingItem(pasteboardWriter: entry.writer())
                let symbol = entry.fileURL == nil ? "doc.text" : "doc"
                let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: entry.title)!
                draggingItem.setDraggingFrame(NSRect(x: origin.x + CGFloat(index % 5) * 3,
                                                     y: origin.y + CGFloat(index % 5) * 3,
                                                     width: 32, height: 32), contents: icon)
                return draggingItem
            }
            let session = beginDraggingSession(with: draggingItems, event: initialEvent, source: self)
            session.draggingFormation = .stack
            session.animatesToStartingPositionsOnCancelOrFail = true
            report?("Dragging \(entries.count) items. Originals stay in place.")
        } catch {
            report?(error.localizedDescription)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        report?(operation.contains(.copy)
                ? "Drop accepted by the destination. Check it there; originals stay in place."
                : "Drag cancelled or not accepted. Originals stay in place.")
    }
}
