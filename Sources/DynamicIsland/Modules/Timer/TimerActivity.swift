import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TimerActivity: LiveActivity {
    let id = "timer"
    let priority = ActivityPriority.high
    private(set) var activatedAt: Date?
    /// Total length, including minutes added while running.
    private(set) var duration: TimeInterval = 0
    /// Set while running.
    private(set) var endDate: Date?
    /// Set while paused.
    private(set) var pausedRemaining: TimeInterval?

    @ObservationIgnored private weak var manager: ActivityManager?
    @ObservationIgnored private var completionTask: Task<Void, Never>?

    init(manager: ActivityManager) {
        self.manager = manager
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    /// Fraction left, 1 at start and 0 when done.
    func progress(at date: Date = .now) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    // MARK: - Controls

    func start(minutes: Double) {
        withAnimation(.islandExpand) {
            duration = minutes * 60
            pausedRemaining = nil
            endDate = .now + duration
            activatedAt = activatedAt ?? .now
        }
        scheduleCompletion()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        completionTask?.cancel()
    }

    func resume() {
        guard let pausedRemaining else { return }
        endDate = .now + pausedRemaining
        self.pausedRemaining = nil
        scheduleCompletion()
    }

    func addMinute() {
        if let endDate {
            self.endDate = endDate + 60
            scheduleCompletion()
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 60
        } else {
            return
        }
        duration += 60
    }

    func stop() {
        completionTask?.cancel()
        withAnimation(.islandCollapse) {
            endDate = nil
            pausedRemaining = nil
            activatedAt = nil
            duration = 0
        }
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        guard let endDate else { return }
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endDate.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled else { return }
            self.finish()
        }
    }

    private func finish() {
        stop()
        NSSound(named: "Glass")?.play()
        manager?.present(TransientEvent(
            id: "timer-done",
            leading: AnyView(Image(systemName: "bell.fill").foregroundStyle(.orange)),
            trailing: AnyView(Text("Done").foregroundStyle(.orange)),
            duration: .seconds(4)
        ))
    }

    /// "4:05" or "1:02:03".
    nonisolated static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - LiveActivity

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: "timer").foregroundStyle(.orange))
    }

    func compactTrailing() -> AnyView {
        AnyView(TimerText(timer: self).foregroundStyle(.orange))
    }

    func minimal() -> AnyView {
        AnyView(TimerRing(timer: self, lineWidth: 3))
    }

    func expanded() -> AnyView {
        AnyView(TimerExpandedView(timer: self))
    }
}
