import Observation
import SwiftUI

/// Decides what the island shows: the primary activity (compact), the secondary
/// one (minimal bubble), and any transient event overriding them for a moment.
@MainActor
@Observable
final class ActivityManager {
    private(set) var activities: [any LiveActivity] = []
    private(set) var transient: TransientEvent?
    private(set) var banner: BannerEvent?
    /// Set while the pointer is over the island so a banner does not vanish mid-read.
    var isBannerHeld = false
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    func register(_ activity: any LiveActivity) {
        activities.append(activity)
    }

    /// Active activities, most important first.
    var ranked: [any LiveActivity] { Self.rank(activities) }
    var primary: (any LiveActivity)? { ranked.first }
    var secondary: (any LiveActivity)? { ranked.dropFirst().first }
    /// Shown on hover when nothing is active, before falling back to Home.
    var dormant: (any LiveActivity)? {
        activities.first { $0.activatedAt == nil && $0.offersExpandedWhileInactive }
    }
    var hasCompactContent: Bool { primary != nil || transient != nil }

    /// Higher priority first; on a tie the activity that started earlier keeps its place.
    static func rank(_ activities: [any LiveActivity]) -> [any LiveActivity] {
        activities
            .compactMap { activity in activity.activatedAt.map { (activity, $0) } }
            .sorted { lhs, rhs in
                lhs.0.priority != rhs.0.priority ? lhs.0.priority > rhs.0.priority : lhs.1 < rhs.1
            }
            .map(\.0)
    }

    /// Shows a banner. A persistent banner (call) is not replaced by a regular one.
    func present(_ event: BannerEvent) {
        if let banner, banner.isPersistent, !event.isPersistent, banner.id != event.id { return }
        bannerTask?.cancel()
        withAnimation(.islandExpand) { banner = event }
        guard !event.isPersistent else { return }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: event.duration)
            while let self, self.isBannerHeld, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let self, !Task.isCancelled else { return }
            self.dismissBanner(id: event.id)
        }
    }

    func dismissBanner(id: String) {
        guard banner?.id == id else { return }
        bannerTask?.cancel()
        withAnimation(.islandCollapse) { banner = nil }
    }

    /// Shows `event` for its duration. A newer event replaces the current one.
    func present(_ event: TransientEvent) {
        transientTask?.cancel()
        withAnimation(.islandExpand) { transient = event }
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: event.duration)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.islandCollapse) { self.transient = nil }
        }
    }
}
