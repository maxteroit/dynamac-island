import Foundation
import IOKit.ps
import Observation
import SwiftUI

struct BatteryStatus: Equatable, Sendable {
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool
}

enum BatteryEvent: Equatable, Sendable {
    case pluggedIn(level: Int)
    case low(level: Int)
}

/// Watches power source changes and posts transient events (charger connected,
/// low battery). Not a persistent activity, like on iPhone.
@MainActor
@Observable
final class BatteryMonitor {
    private(set) var status: BatteryStatus?

    @ObservationIgnored private weak var manager: ActivityManager?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    /// Checked from highest to lowest.
    nonisolated static let lowLevelThresholds = [20, 10]

    init(manager: ActivityManager) {
        self.manager = manager
        status = Self.read()
        startObserving()
    }

    private func startObserving() {
        // Lives for the whole app run, so an unretained pointer is safe.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the main run loop.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private func refresh() {
        guard let new = Self.read() else { return }
        let old = status
        status = new
        Self.events(from: old, to: new).forEach(present)
    }

    /// Shows the charging alert without plugging in. Dev menu only.
    func simulatePlugIn() {
        present(.pluggedIn(level: status?.level ?? 80))
    }

    nonisolated static func events(from old: BatteryStatus?, to new: BatteryStatus) -> [BatteryEvent] {
        guard let old, new.hasBattery else { return [] }
        if new.isPluggedIn && !old.isPluggedIn {
            return [.pluggedIn(level: new.level)]
        }
        let crossedThreshold = lowLevelThresholds.contains { new.level <= $0 && old.level > $0 }
        if !new.isPluggedIn && crossedThreshold {
            return [.low(level: new.level)]
        }
        return []
    }

    nonisolated static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryStatus(
                level: max > 0 ? current * 100 / max : 0,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                hasBattery: true
            )
        }
        return BatteryStatus(level: 100, isCharging: false, isPluggedIn: true, hasBattery: false)
    }

    private func present(_ event: BatteryEvent) {
        switch event {
        case .pluggedIn(let level):
            manager?.present(TransientEvent(
                id: "battery-charging",
                leading: AnyView(Image(systemName: "bolt.fill").foregroundStyle(.green)),
                trailing: AnyView(BatteryLabel(level: level, color: .green))
            ))
        case .low(let level):
            manager?.present(TransientEvent(
                id: "battery-low",
                leading: AnyView(Text("Low Battery").foregroundStyle(.red)),
                trailing: AnyView(BatteryLabel(level: level, color: .red)),
                duration: .seconds(4)
            ))
        }
    }
}
