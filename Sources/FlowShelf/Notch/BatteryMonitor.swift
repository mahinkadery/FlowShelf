import Foundation
import IOKit.ps

/// Watches the power source and emits notch HUD events: a charging live activity
/// when the adapter is plugged in, and a low-battery warning on the way down.
@MainActor
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    var onEvent: ((NotchHUD) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lastPluggedIn: Bool?
    private var lowWarned = false
    private var running = false

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        lastPluggedIn = readState()?.pluggedIn        // seed without firing

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            let me = Unmanaged<BatteryMonitor>.fromOpaque(raw).takeUnretainedValue()
            Task { @MainActor in me.handleChange() }
        }, ctx)?.takeRetainedValue() else { return }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func stop() {
        running = false
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
        runLoopSource = nil
        lastPluggedIn = nil
        lowWarned = false
    }

    private struct State { var pluggedIn: Bool; var percent: Int; var charging: Bool; var full: Bool }

    private func readState() -> State? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            let cur = d[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            let plugged = (d[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            let charging = d[kIOPSIsChargingKey as String] as? Bool ?? false
            let full = pct >= 100 || (d[kIOPSIsChargedKey as String] as? Bool ?? false)
            return State(pluggedIn: plugged, percent: pct, charging: charging, full: full)
        }
        return nil
    }

    private func handleChange() {
        guard let s = readState() else { return }
        if lastPluggedIn != s.pluggedIn {
            lastPluggedIn = s.pluggedIn
            if s.pluggedIn {
                onEvent?(.charging(percent: s.percent, charging: s.charging, full: s.full))
            }
        }
        if !s.pluggedIn, s.percent <= 20, !lowWarned {
            lowWarned = true
            onEvent?(.lowBattery(percent: s.percent))
        }
        if s.percent > 25 { lowWarned = false }
    }

    /// Current charge as a HUD (used by the debug/preview trigger).
    func chargingSnapshot() -> NotchHUD? {
        guard let s = readState() else { return nil }
        return .charging(percent: s.percent, charging: s.charging, full: s.full)
    }
}
