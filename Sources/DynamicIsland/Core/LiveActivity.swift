import SwiftUI

enum ActivityPriority: Int, Comparable, Sendable {
    case low, normal, high, critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CompactStyle: Sendable {
    /// Content on both sides of the notch.
    case full
    /// Content only to the right of the notch, keeping the left menu bar clear.
    case trailingOnly
}

/// A module that can occupy the island, mirroring iPhone Live Activities.
/// Conforming types should be `@Observable` so the island reacts to changes.
@MainActor
protocol LiveActivity: AnyObject {
    var id: String { get }
    var priority: ActivityPriority { get }
    /// Nil while inactive. Orders activities that share a priority.
    var activatedAt: Date? { get }
    var compactStyle: CompactStyle { get }
    /// True when the activity is hidden from the compact island but should still
    /// open on hover (paused music that can be resumed).
    var offersExpandedWhileInactive: Bool { get }

    func compactLeading() -> AnyView
    func compactTrailing() -> AnyView
    /// Content of the detached bubble when this is the secondary activity.
    func minimal() -> AnyView
    func expanded() -> AnyView
}

extension LiveActivity {
    var compactStyle: CompactStyle { .full }
    var offersExpandedWhileInactive: Bool { false }
}

/// Card that drops out of the notch (message, incoming call), like iPhone
/// notifications. Takes precedence over every other state while shown.
struct BannerEvent: Identifiable {
    let id: String
    let content: AnyView
    /// Calls stay until dismissed; messages expire after `duration`.
    var isPersistent = false
    var duration: Duration = .seconds(5)
    /// Clicking the card (outside its buttons).
    var onTap: (() -> Void)?
}

/// Short-lived compact content (charger connected, timer done) that temporarily
/// replaces the primary activity, like the iPhone's system alerts.
struct TransientEvent: Identifiable {
    let id: String
    let leading: AnyView
    let trailing: AnyView
    var duration: Duration = .seconds(2.5)
}
