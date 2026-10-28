import AppKit
import Observation
import SwiftUI

extension Animation {
    static let islandExpand = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let islandCollapse = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let islandPeek = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

/// Modules the island UI talks to directly (Home view, dev menu).
@MainActor
struct IslandModules {
    let timer: TimerActivity
    let battery: BatteryMonitor
    let nowPlaying: NowPlayingActivity
    let demo: DemoActivity
}

@MainActor
@Observable
final class IslandViewModel {
    let activities: ActivityManager
    let modules: IslandModules
    var metrics = IslandMetrics(notchSize: CGSize(width: NotchGeometry.fallbackWidth, height: NotchGeometry.fallbackHeight))
    private(set) var isExpanded = false
    private(set) var isPeeking = false
    /// Activity picked by tapping the bubble. Nil means the primary activity.
    private(set) var expandedActivityID: String?
    var expandOnHover = true

    @ObservationIgnored private var isPointerInside = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    static let peekDelay: Duration = .milliseconds(120)
    static let hoverExpandDelay: Duration = .milliseconds(150)
    static let collapseGrace: Duration = .milliseconds(150)

    init(activities: ActivityManager, modules: IslandModules) {
        self.activities = activities
        self.modules = modules
    }

    var state: IslandState {
        if activities.banner != nil { return .banner }
        if isExpanded { return .expanded }
        return activities.hasCompactContent ? .compact : .idle
    }

    var showsBubble: Bool {
        state == .compact && activities.secondary != nil
    }

    /// Transient events always use both sides; otherwise the primary activity decides.
    var compactStyle: CompactStyle {
        guard activities.transient == nil else { return .full }
        return activities.primary?.compactStyle ?? .full
    }

    var layout: IslandLayout {
        metrics.layout(for: state, peeking: isPeeking, showsBubble: showsBubble, compactStyle: compactStyle)
    }

    var isVisible: Bool {
        metrics.isVisible(state: state, peeking: isPeeking)
    }

    /// Activity rendered in the expanded panel. Nil shows the Home view.
    var expandedActivity: (any LiveActivity)? {
        if let id = expandedActivityID, let picked = activities.ranked.first(where: { $0.id == id }) {
            return picked
        }
        return activities.primary ?? activities.dormant
    }

    // MARK: - Pointer

    func pointerEntered() {
        guard !isPointerInside else { return }
        isPointerInside = true
        hoverTask?.cancel()
        activities.isBannerHeld = true
        guard state != .expanded, state != .banner else { return }

        hoverTask = Task { [weak self] in
            guard let self else { return }
            if self.expandOnHover {
                // Expand straight from the notch; the short delay ignores a pointer
                // just passing by on its way to the menu bar.
                try? await Task.sleep(for: Self.hoverExpandDelay)
                guard !Task.isCancelled, self.isPointerInside else { return }
                self.expand()
            } else {
                // Click-to-expand mode: peek to show the island is interactive.
                try? await Task.sleep(for: Self.peekDelay)
                guard !Task.isCancelled, self.isPointerInside else { return }
                withAnimation(.islandPeek) { self.isPeeking = true }
            }
        }
    }

    func pointerExited() {
        guard isPointerInside else { return }
        isPointerInside = false
        hoverTask?.cancel()
        activities.isBannerHeld = false

        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseGrace)
            guard let self, !Task.isCancelled, !self.isPointerInside else { return }
            self.collapse()
        }
    }

    // MARK: - Transitions

    /// Click on the island: opens a banner's source, otherwise expands.
    func tap() {
        if let banner = activities.banner {
            banner.onTap?()
            activities.dismissBanner(id: banner.id)
        } else {
            expand()
        }
    }

    func expand(activityID: String? = nil) {
        hoverTask?.cancel()
        if activityID != nil { expandedActivityID = activityID }
        guard !isExpanded else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.islandExpand) {
            isExpanded = true
            isPeeking = false
        }
    }

    func collapse() {
        guard isExpanded || isPeeking else { return }
        withAnimation(.islandCollapse) {
            isExpanded = false
            isPeeking = false
            expandedActivityID = nil
        }
    }
}
