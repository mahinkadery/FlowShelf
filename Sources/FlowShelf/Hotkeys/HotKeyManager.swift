import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey.
/// Works without Accessibility permission (unlike NSEvent global monitors for keys).
///
/// Every action's combo is user-customizable (see `ShortcutRecorder` in
/// Settings): specs persist in UserDefaults, re-register instantly on change,
/// in-app duplicates are surfaced, and registration failures (macOS/system/apps
/// already owning a combo) are tracked per action for an honest warning.
@MainActor
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    enum Action: UInt32, CaseIterable, Codable {
        case toggleShelf = 1
        case openSearch = 2
        case screenshot = 3
        case ocr = 4
        case dashboard = 5

        var label: String {
            switch self {
            case .toggleShelf: return "Show floating shelf"
            case .openSearch: return "Open shelf search"
            case .screenshot: return "Screenshot region"
            case .ocr: return "Screenshot + OCR"
            case .dashboard: return "Open dashboard"
            }
        }
    }

    static func defaultSpec(for action: Action) -> ShortcutSpec {
        let cmdShift = UInt32(cmdKey | shiftKey)
        switch action {
        case .toggleShelf: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_S), mods: cmdShift)
        case .openSearch: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_V), mods: cmdShift)
        case .screenshot: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_7), mods: cmdShift)
        case .ocr: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_O), mods: cmdShift)
        case .dashboard: return ShortcutSpec(keyCode: UInt32(kVK_ANSI_D), mods: cmdShift)
        }
    }

    /// Actions whose last registration was refused by macOS (combo owned by the
    /// system or another app). Drives the ⚠️ in Settings.
    @Published private(set) var failedActions: Set<Action> = []
    /// Bumped whenever specs change so recorder rows refresh.
    @Published private(set) var revision = 0

    private var specs: [Action: ShortcutSpec] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var suspended = false
    var onAction: ((Action) -> Void)?

    private let signature: OSType = {
        let s = "FLSF"
        return s.utf16.reduce(0) { ($0 << 8) + OSType($1) }
    }()
    private static let defaultsKey = "customHotkeys"

    private init() {
        specs = Self.load()
    }

    // MARK: Specs

    func spec(for action: Action) -> ShortcutSpec {
        specs[action] ?? Self.defaultSpec(for: action)
    }

    /// Actions (other than `action`) already using `spec` — in-app conflicts.
    func conflicts(of spec: ShortcutSpec, excluding action: Action) -> [Action] {
        Action.allCases.filter { $0 != action && self.spec(for: $0) == spec }
    }

    func set(_ newSpec: ShortcutSpec, for action: Action) {
        specs[action] = newSpec
        persist()
        registerAll()
        revision += 1
    }

    func reset(_ action: Action) {
        specs.removeValue(forKey: action)
        persist()
        registerAll()
        revision += 1
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(specs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load() -> [Action: ShortcutSpec] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let specs = try? JSONDecoder().decode([Action: ShortcutSpec].self, from: data)
        else { return [:] }
        return specs
    }

    // MARK: Registration

    /// Register every action's current (stored or default) combo.
    func registerAll() {
        installHandler()
        unregisterAll()
        guard !suspended else { return }
        var failed: Set<Action> = []
        for action in Action.allCases {
            let s = spec(for: action)
            if !register(id: action.rawValue, keyCode: s.keyCode, mods: s.mods) {
                failed.insert(action)
            }
        }
        failedActions = failed
    }

    /// Kept for existing call sites; registers the current (customized) combos.
    func registerDefaults() { registerAll() }

    /// Temporarily drop all hotkeys (used while recording a new combo, so the
    /// keystroke being tried can't fire an action mid-capture).
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        registerAll()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Only handle our own hotkeys; otherwise let the event fall through to
            // other registered handlers (e.g. the window snapper, whose ids overlap).
            guard hkID.signature == manager.signature, let action = Action(rawValue: hkID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { manager.onAction?(action) }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    private func register(id: UInt32, keyCode: UInt32, mods: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, mods, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            refs.append(ref)
            return true
        }
        NSLog("FlowShelf: failed to register hotkey \(id) (status \(status))")
        return false
    }

    func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
}
