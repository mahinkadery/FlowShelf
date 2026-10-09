import AppKit
import Combine

@MainActor
final class NotchPresentationState: ObservableObject {
    static let shared = NotchPresentationState()
    @Published private(set) var suspended = false
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var locked = false
    private var sleeping = false

    private init() {
        let distributed = DistributedNotificationCenter.default()
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.locked = value
                    self.suspended = self.locked || self.sleeping
                }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, value) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.sleeping = value
                    self.suspended = self.locked || self.sleeping
                }
            }
        }
        workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        }
    }
}

@MainActor
final class NotchViewActivity {
    private weak var view: NSView?
    private var observations: [NSObjectProtocol] = []
    private var stateSubscription: AnyCancellable?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    var isVisible: Bool {
        guard let view, let window = view.window else { return false }
        return Self.isVisible(windowVisible: window.isVisible,
                              occluded: !window.occlusionState.contains(.visible),
                              miniaturized: window.isMiniaturized,
                              hidden: view.isHiddenOrHasHiddenAncestor,
                              suspended: NotchPresentationState.shared.suspended)
    }

    static func isVisible(windowVisible: Bool, occluded: Bool, miniaturized: Bool, hidden: Bool, suspended: Bool) -> Bool {
        windowVisible && !occluded && !miniaturized && !hidden && !suspended
    }

    func attach(to view: NSView?) {
        detach()
        self.view = view
        guard let window = view?.window else { onChange(); return }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, .NSProcessInfoPowerStateDidChange] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: name == .NSProcessInfoPowerStateDidChange ? nil : window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange() }
            })
        }
        stateSubscription = NotchPresentationState.shared.$suspended
            .combineLatest(NotchPresentationState.shared.$reduceMotion)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.onChange() }
        onChange()
    }

    func detach() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        stateSubscription = nil
        view = nil
    }

    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
}

struct NotchLensRenderKey: Equatable {
    let generation: UInt64
    let frame: UInt64
    let crop: CGRect
    let scale: CGFloat
}
