import SwiftUI

struct NotchMarqueeCycle: Equatable {
    let textWidth: CGFloat
    let availableWidth: CGFloat
    let gap: CGFloat
    let active: Bool

    var running: Bool {
        active && textWidth.isFinite && availableWidth.isFinite && gap.isFinite
            && availableWidth > 0 && gap >= 0 && textWidth > availableWidth + 1
    }

    func offset(elapsed: TimeInterval) -> CGFloat {
        guard running, elapsed.isFinite, elapsed > 0 else { return 0 }
        let travel = Double(textWidth + gap)
        let phase = elapsed.truncatingRemainder(dividingBy: 2 + travel / 24)
        return -CGFloat(min(travel, max(0, phase - 2) * 24))
    }
}

struct NotchVisibilityReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Reporter {
        let view = Reporter()
        view.onChange = { visible = $0 }
        return view
    }

    func updateNSView(_ view: Reporter, context: Context) {
        view.onChange = { visible = $0 }
    }

    static func dismantleNSView(_ view: Reporter, coordinator: ()) {
        view.stop()
    }

    final class Reporter: NSView {
        var onChange: ((Bool) -> Void)?
        private var pendingReport: DispatchWorkItem?
        private var lastReported: Bool?
        private lazy var activity = NotchViewActivity { [weak self] in self?.report() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activity.attach(to: self)
        }

        override func viewDidHide() { super.viewDidHide(); report() }
        override func viewDidUnhide() { super.viewDidUnhide(); report() }

        private func report() {
            pendingReport?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingReport = nil
                let visible = self.activity.isVisible
                guard self.lastReported != visible else { return }
                self.lastReported = visible
                self.onChange?(visible)
            }
            pendingReport = work
            DispatchQueue.main.async(execute: work)
        }

        func stop() {
            activity.detach()
            pendingReport?.cancel()
            pendingReport = nil
            onChange = nil
        }
    }
}
