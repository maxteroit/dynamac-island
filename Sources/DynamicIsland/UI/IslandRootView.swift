import SwiftUI

/// Fills the fixed-size panel and pins the island to the top center.
struct IslandRootView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IslandView: View {
    let model: IslandViewModel

    var body: some View {
        let layout = model.layout
        let shape = IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius)

        ZStack(alignment: .top) {
            shape.fill(.black)
            content(layout: layout)
        }
        .frame(width: layout.shapeSize.width, height: layout.shapeSize.height)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(model.state == .expanded || model.state == .banner ? 0.45 : 0), radius: 14, y: 6)
        .onTapGesture { model.tap() }
        // Overlay keeps the island centered on the notch while the bubble hangs to its right.
        .overlay(alignment: .topTrailing) {
            if layout.bubbleSize != .zero, let secondary = model.activities.secondary {
                MinimalBubble(size: layout.bubbleSize) { secondary.minimal() }
                    .offset(x: layout.bubbleSize.width + IslandMetrics.bubbleSpacing)
                    .onTapGesture { model.expand(activityID: secondary.id) }
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
            }
        }
        .offset(x: layout.horizontalOffset)
        .opacity(model.isVisible ? 1 : 0)
    }

    @ViewBuilder
    private func content(layout: IslandLayout) -> some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .compact:
            if let event = model.activities.transient {
                CompactRow(layout: layout, leading: event.leading, trailing: event.trailing)
                    .id("transient-\(event.id)")
                    .transition(.islandContent)
            } else if let primary = model.activities.primary {
                CompactRow(
                    layout: layout,
                    leading: primary.compactStyle == .full ? primary.compactLeading() : AnyView(EmptyView()),
                    trailing: primary.compactTrailing()
                )
                .id(primary.id)
                .transition(.islandContent)
            }
        case .banner:
            if let banner = model.activities.banner {
                banner.content
                    .id(banner.id)
                    .padding(.top, model.metrics.notchSize.height + 6)
                    .padding(.horizontal, layout.topRadius + 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .transition(.islandContent)
            }
        case .expanded:
            Group {
                if let activity = model.expandedActivity {
                    activity.expanded().id(activity.id)
                } else {
                    HomeView(timer: model.modules.timer, battery: model.modules.battery)
                }
            }
            .padding(.top, model.metrics.notchSize.height + 8)
            .padding(.horizontal, layout.topRadius + 22)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .transition(.islandContent)
        }
    }
}

/// Leading and trailing content on either side of the camera housing.
struct CompactRow: View {
    let layout: IslandLayout
    let leading: AnyView
    let trailing: AnyView

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, layout.topRadius + 12)
        .frame(maxHeight: .infinity)
    }
}

struct MinimalBubble<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            IslandShape(topRadius: IslandMetrics.bubbleTopRadius, bottomRadius: size.height / 2)
                .fill(.black)
            content
                .padding(.horizontal, IslandMetrics.bubbleTopRadius + 6)
                .padding(.vertical, 6)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
}

extension AnyTransition {
    @MainActor static let islandContent = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .scale(scale: 0.85, anchor: .top))
            .animation(.islandExpand.delay(0.06)),
        removal: .opacity.animation(.easeOut(duration: 0.12))
    )
}
