import CoreGraphics

enum IslandState: Equatable, Sendable {
    /// Same size as the physical notch, effectively invisible.
    case idle
    /// Notch widened left and right to show a live activity.
    case compact
    /// Large panel below the notch.
    case expanded
    /// Notification card below the notch.
    case banner
}

struct IslandLayout: Equatable, Sendable {
    /// Body size, excluding the flared top corners.
    var size: CGSize
    /// Radius of the concave corners where the island meets the top bezel.
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Detached bubble for the secondary activity (minimal presentation). Zero when hidden.
    var bubbleSize: CGSize = .zero
    /// Shift from the notch center; positive moves right (trailing-only compact).
    var horizontalOffset: CGFloat = 0

    /// Full drawn size, including the flared top corners.
    var shapeSize: CGSize {
        CGSize(width: size.width + topRadius * 2, height: size.height)
    }

    /// Island plus bubble in screen coordinates (origin bottom-left), hanging from `top`.
    func hitRect(midX: CGFloat, top: CGFloat) -> CGRect {
        let island = CGRect(
            x: midX + horizontalOffset - shapeSize.width / 2,
            y: top - shapeSize.height,
            width: shapeSize.width,
            height: shapeSize.height
        )
        guard bubbleSize != .zero else { return island }
        let bubble = CGRect(
            x: island.maxX + IslandMetrics.bubbleSpacing,
            y: top - bubbleSize.height,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        return island.union(bubble)
    }
}

struct IslandMetrics: Equatable, Sendable {
    var notchSize: CGSize
    /// True on displays with a camera housing. The idle island then hides
    /// behind the physical notch instead of drawing its own.
    var hasPhysicalNotch = false

    static let compactSideWidth: CGFloat = 72
    static let trailingOnlyWidth: CGFloat = 44
    static let expandedSize = CGSize(width: 480, height: 190)
    static let bannerWidth: CGFloat = 400
    /// Card height below the notch.
    static let bannerContentHeight: CGFloat = 68
    static let peekGrowth = CGSize(width: 16, height: 5)
    static let bubbleSpacing: CGFloat = 6
    static let bubbleTopRadius: CGFloat = 6

    /// Fixed window size: the largest layout plus room for spring overshoot.
    /// The window never resizes; SwiftUI animates the shape inside it.
    static let windowSize = CGSize(width: expandedSize.width + 80, height: expandedSize.height + 40)

    func layout(
        for state: IslandState,
        peeking: Bool,
        showsBubble: Bool = false,
        compactStyle: CompactStyle = .full
    ) -> IslandLayout {
        var layout: IslandLayout
        switch state {
        case .idle:
            layout = IslandLayout(size: notchSize, topRadius: hasPhysicalNotch ? 0 : 6, bottomRadius: 10)
        case .compact where compactStyle == .trailingOnly:
            // Grows only to the right; the left edge stays on the notch edge.
            layout = IslandLayout(
                size: CGSize(width: notchSize.width + Self.trailingOnlyWidth, height: notchSize.height),
                topRadius: 6,
                bottomRadius: 12,
                horizontalOffset: Self.trailingOnlyWidth / 2
            )
        case .compact:
            layout = IslandLayout(
                size: CGSize(width: notchSize.width + Self.compactSideWidth * 2, height: notchSize.height),
                topRadius: 6,
                bottomRadius: 12
            )
        case .banner:
            layout = IslandLayout(
                size: CGSize(
                    width: max(Self.bannerWidth, notchSize.width + Self.compactSideWidth * 2),
                    height: notchSize.height + Self.bannerContentHeight
                ),
                topRadius: 12,
                bottomRadius: 26
            )
        case .expanded:
            layout = IslandLayout(
                size: CGSize(
                    width: max(Self.expandedSize.width, notchSize.width + Self.compactSideWidth * 2),
                    height: max(Self.expandedSize.height, notchSize.height + 100)
                ),
                topRadius: 14,
                bottomRadius: 32
            )
        }
        if peeking && (state == .idle || state == .compact) {
            layout.size.width += Self.peekGrowth.width
            layout.size.height += Self.peekGrowth.height
            layout.bottomRadius += 2
        }
        if showsBubble && state == .compact {
            layout.bubbleSize = CGSize(
                width: notchSize.height + Self.bubbleTopRadius * 2,
                height: layout.size.height
            )
        }
        return layout
    }

    /// Whether the island draws anything for the given state.
    func isVisible(state: IslandState, peeking: Bool) -> Bool {
        !(hasPhysicalNotch && state == .idle && !peeking)
    }
}
