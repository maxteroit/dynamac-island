import CoreGraphics
import Foundation
import OSLog

/// Shows a brightness HUD for the built-in display. Uses the private
/// DisplayServices framework read-only; the module disables itself if the
/// symbols are missing. Observe-only: the system bezel still appears too.
@MainActor
final class BrightnessMonitor {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias ChangeCallback = @convention(c) (
        CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?
    ) -> Void
    private typealias RegisterForChanges = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, ChangeCallback) -> Int32

    /// Target for the C callback, which cannot capture context.
    private static weak var current: BrightnessMonitor?

    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "HUD")
    private weak var manager: ActivityManager?
    private let display: CGDirectDisplayID
    private let getBrightness: GetBrightness
    private var filter = BrightnessChangeFilter()

    init?(manager: ActivityManager) {
        guard let display = Self.builtInDisplay(),
              let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let registerSymbol = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications")
        else { return nil }

        self.manager = manager
        self.display = display
        getBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
        if let level = readBrightness() {
            filter.record(level, at: .now)
        }

        Self.current = self
        let register = unsafeBitCast(registerSymbol, to: RegisterForChanges.self)
        // The callback ignores its arguments and re-reads the level, so it does not
        // depend on the exact private payload.
        let status = register(display, UnsafeMutableRawPointer(bitPattern: UInt(display)), { _, _, _, _, _ in
            Task { @MainActor in BrightnessMonitor.current?.brightnessChanged() }
        })
        if status != 0 {
            logger.error("Brightness notifications unavailable (status \(status))")
        }
    }

    private func brightnessChanged() {
        guard let level = readBrightness() else { return }
        let showing = manager?.transient?.id == "hud-\(HUDKind.brightness.rawValue)"
        if filter.record(level, at: .now) || showing {
            manager?.present(HUD.event(kind: .brightness, level: level))
        }
    }

    private func readBrightness() -> Float? {
        var level: Float = 0
        return getBrightness(display, &level) == 0 ? level : nil
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// Separates user changes (keys, Control Center: a step of ~6% within a moment)
/// from auto-brightness, which drifts slowly and should not pop up a HUD.
struct BrightnessChangeFilter {
    static let window: TimeInterval = 0.4
    static let minimumStep: Float = 0.03

    private var samples: [(date: Date, level: Float)] = []

    /// Records a reading; returns true when it looks like a deliberate change.
    @discardableResult
    mutating func record(_ level: Float, at date: Date) -> Bool {
        // After a quiet period the last known level is the reference, so the
        // first callback of a key press already counts.
        let lastKnown = samples.last?.level
        samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
        let reference = samples.first?.level ?? lastKnown ?? level
        samples.append((date, level))
        return abs(level - reference) >= Self.minimumStep
    }
}
