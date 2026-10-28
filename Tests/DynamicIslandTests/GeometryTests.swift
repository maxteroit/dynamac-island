import CoreGraphics
import Testing
@testable import DynamicIsland

struct NotchGeometryTests {
    @Test func notchedScreenUsesGapBetweenAuxiliaryAreas() {
        let size = NotchGeometry.notchSize(
            screenWidth: 1512, leftAreaWidth: 663, rightAreaWidth: 664,
            safeAreaTop: 32, menuBarHeight: 32
        )
        #expect(size == CGSize(width: 185, height: 32))
    }

    @Test func screenWithoutNotchFallsBackToMenuBarHeight() {
        let size = NotchGeometry.notchSize(
            screenWidth: 1920, leftAreaWidth: nil, rightAreaWidth: nil,
            safeAreaTop: 0, menuBarHeight: 25
        )
        #expect(size == CGSize(width: NotchGeometry.fallbackWidth, height: 25))
    }

    @Test func autoHiddenMenuBarUsesDefaultHeight() {
        let size = NotchGeometry.notchSize(
            screenWidth: 1920, leftAreaWidth: nil, rightAreaWidth: nil,
            safeAreaTop: 0, menuBarHeight: 0
        )
        #expect(size.height == NotchGeometry.fallbackHeight)
    }
}

struct IslandMetricsTests {
    let metrics = IslandMetrics(notchSize: CGSize(width: 185, height: 32))

    @Test func idleMatchesNotch() {
        #expect(metrics.layout(for: .idle, peeking: false).size == CGSize(width: 185, height: 32))
    }

    @Test func compactWidensBothSidesKeepingHeight() {
        let layout = metrics.layout(for: .compact, peeking: false)
        #expect(layout.size.width == 185 + IslandMetrics.compactSideWidth * 2)
        #expect(layout.size.height == 32)
    }

    @Test func peekGrowsIdleAndCompactButNotExpanded() {
        for state in [IslandState.idle, .compact] {
            let base = metrics.layout(for: state, peeking: false).size
            let peek = metrics.layout(for: state, peeking: true).size
            #expect(peek.width > base.width)
            #expect(peek.height > base.height)
        }
        #expect(metrics.layout(for: .expanded, peeking: true) == metrics.layout(for: .expanded, peeking: false))
    }

    @Test func idleHidesBehindPhysicalNotchOnly() {
        let notched = IslandMetrics(notchSize: CGSize(width: 185, height: 32), hasPhysicalNotch: true)
        #expect(!notched.isVisible(state: .idle, peeking: false))
        #expect(notched.isVisible(state: .expanded, peeking: false))
        #expect(notched.isVisible(state: .compact, peeking: false))
        #expect(notched.layout(for: .idle, peeking: false).shapeSize == CGSize(width: 185, height: 32))
        #expect(metrics.isVisible(state: .idle, peeking: false))
    }

    @Test func bubbleOnlyInCompactAndExtendsHitRectToTheRight() {
        #expect(metrics.layout(for: .expanded, peeking: false, showsBubble: true).bubbleSize == .zero)

        let plain = metrics.layout(for: .compact, peeking: false)
        let withBubble = metrics.layout(for: .compact, peeking: false, showsBubble: true)
        #expect(withBubble.bubbleSize.height == plain.size.height)

        let plainRect = plain.hitRect(midX: 0, top: 100)
        let bubbleRect = withBubble.hitRect(midX: 0, top: 100)
        #expect(bubbleRect.minX == plainRect.minX)
        #expect(bubbleRect.maxX == plainRect.maxX + IslandMetrics.bubbleSpacing + withBubble.bubbleSize.width)
        #expect(bubbleRect.maxY == 100)
    }

    @Test func trailingOnlyCompactKeepsLeftEdgeOnNotch() {
        let layout = metrics.layout(for: .compact, peeking: false, compactStyle: .trailingOnly)
        let bodyLeft = layout.horizontalOffset - layout.size.width / 2
        #expect(bodyLeft == -metrics.notchSize.width / 2)
        #expect(layout.size.width == metrics.notchSize.width + IslandMetrics.trailingOnlyWidth)

        let rect = layout.hitRect(midX: 0, top: 0)
        #expect(rect.minX == -metrics.notchSize.width / 2 - layout.topRadius)
        #expect(rect.maxX == metrics.notchSize.width / 2 + IslandMetrics.trailingOnlyWidth + layout.topRadius)
    }

    @Test func trailingOnlyIgnoredOutsideCompact() {
        #expect(metrics.layout(for: .expanded, peeking: false, compactStyle: .trailingOnly).horizontalOffset == 0)
        #expect(metrics.layout(for: .idle, peeking: false, compactStyle: .trailingOnly).horizontalOffset == 0)
    }

    @Test func compactWithBubbleFitsInsideWindow() {
        let rect = metrics.layout(for: .compact, peeking: true, showsBubble: true).hitRect(midX: 0, top: 0)
        #expect(rect.maxX <= IslandMetrics.windowSize.width / 2)
    }

    @Test func everyLayoutFitsInsideWindow() {
        for state in [IslandState.idle, .compact, .expanded] {
            for peeking in [false, true] {
                let shape = metrics.layout(for: state, peeking: peeking).shapeSize
                #expect(shape.width <= IslandMetrics.windowSize.width)
                #expect(shape.height <= IslandMetrics.windowSize.height)
            }
        }
    }
}
