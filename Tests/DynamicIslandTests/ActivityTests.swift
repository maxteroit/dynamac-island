import Foundation
import SwiftUI
import Testing
@testable import DynamicIsland

@MainActor
private final class StubActivity: LiveActivity {
    let id: String
    let priority: ActivityPriority
    var activatedAt: Date?
    var offersExpandedWhileInactive = false

    init(_ id: String, _ priority: ActivityPriority, activatedAt: Date?) {
        self.id = id
        self.priority = priority
        self.activatedAt = activatedAt
    }

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func minimal() -> AnyView { AnyView(EmptyView()) }
    func expanded() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct ActivityManagerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func rankSkipsInactiveAndOrdersByPriorityThenStartTime() {
        let activities: [any LiveActivity] = [
            StubActivity("inactive", .critical, activatedAt: nil),
            StubActivity("normal-late", .normal, activatedAt: t0 + 10),
            StubActivity("high", .high, activatedAt: t0 + 20),
            StubActivity("normal-early", .normal, activatedAt: t0),
        ]
        #expect(ActivityManager.rank(activities).map(\.id) == ["high", "normal-early", "normal-late"])
    }

    @Test func primaryAndSecondaryFollowRanking() {
        let manager = ActivityManager()
        let low = StubActivity("low", .low, activatedAt: t0)
        let high = StubActivity("high", .high, activatedAt: t0 + 5)
        manager.register(low)
        manager.register(high)
        #expect(manager.primary?.id == "high")
        #expect(manager.secondary?.id == "low")

        high.activatedAt = nil
        #expect(manager.primary?.id == "low")
        #expect(manager.secondary == nil)
    }

    @Test func dormantOnlyWhenInactiveAndOffering() {
        let manager = ActivityManager()
        let music = StubActivity("music", .normal, activatedAt: nil)
        manager.register(StubActivity("timer", .high, activatedAt: nil))
        manager.register(music)
        #expect(manager.dormant == nil)

        music.offersExpandedWhileInactive = true
        #expect(manager.dormant?.id == "music")
        #expect(!manager.hasCompactContent)

        music.activatedAt = t0
        #expect(manager.dormant == nil)
    }

    @Test func transientExpiresAfterDuration() async throws {
        let manager = ActivityManager()
        manager.present(TransientEvent(
            id: "test", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
            duration: .milliseconds(50)
        ))
        #expect(manager.transient?.id == "test")
        #expect(manager.hasCompactContent)
        try await Task.sleep(for: .milliseconds(250))
        #expect(manager.transient == nil)
        #expect(!manager.hasCompactContent)
    }
}

struct BatteryEventTests {
    let unplugged = BatteryStatus(level: 50, isCharging: false, isPluggedIn: false, hasBattery: true)

    @Test func plugInEmitsChargingEvent() {
        var plugged = unplugged
        plugged.isPluggedIn = true
        #expect(BatteryMonitor.events(from: unplugged, to: plugged) == [.pluggedIn(level: 50)])
    }

    @Test func firstReadingEmitsNothing() {
        #expect(BatteryMonitor.events(from: nil, to: unplugged).isEmpty)
    }

    @Test func crossingLowThresholdEmitsOnce() {
        var at21 = unplugged; at21.level = 21
        var at20 = unplugged; at20.level = 20
        var at19 = unplugged; at19.level = 19
        #expect(BatteryMonitor.events(from: at21, to: at20) == [.low(level: 20)])
        #expect(BatteryMonitor.events(from: at20, to: at19).isEmpty)
    }

    @Test func lowLevelIgnoredWhilePluggedIn() {
        var before = unplugged; before.level = 21; before.isPluggedIn = true
        var after = before; after.level = 20
        #expect(BatteryMonitor.events(from: before, to: after).isEmpty)
    }
}

struct TimerFormatTests {
    @Test(arguments: [
        (0.0, "0:00"),
        (59.2, "1:00"),
        (245, "4:05"),
        (3723, "1:02:03"),
    ])
    func formatsClock(seconds: TimeInterval, expected: String) {
        #expect(TimerActivity.format(seconds) == expected)
    }
}
