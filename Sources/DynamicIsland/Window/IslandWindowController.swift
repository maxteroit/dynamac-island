import AppKit
import Observation
import OSLog
import SwiftUI

@MainActor
final class IslandWindowController {
    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "Window")
    private let panel = IslandPanel()
    private let viewModel: IslandViewModel
    private var screen: NSScreen
    private var globalMonitor: Any?

    /// Extra hover zone below the island so the pointer does not need to hit the exact edge.
    private let hoverMargin: CGFloat = 6

    init(screen: NSScreen, viewModel: IslandViewModel) {
        self.screen = screen
        self.viewModel = viewModel

        let container = TrackingContainerView()
        let hostingView = FirstMouseHostingView(rootView: IslandRootView(model: viewModel))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        container.onPointerMove = { [weak self] in self?.updatePointer() }
        panel.contentView = container

        move(to: screen)
        panel.orderFrontRegardless()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        observeLayout()
    }

    func move(to screen: NSScreen) {
        self.screen = screen
        viewModel.metrics = IslandMetrics(notchSize: screen.notchSize, hasPhysicalNotch: screen.hasNotch)

        let size = IslandMetrics.windowSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        panel.contentView?.subviews.first?.frame = CGRect(origin: .zero, size: size)
        logger.info("Island on \(screen.localizedName, privacy: .public), notch \(screen.notchSize.debugDescription, privacy: .public)")
        updatePointer()
    }

    /// Island (and bubble) frame in screen coordinates, based on the target (post-animation) layout.
    private var hotRect: CGRect {
        var rect = viewModel.layout.hitRect(midX: screen.frame.midX, top: screen.frame.maxY)
        rect.origin.y -= hoverMargin
        rect.size.height += hoverMargin
        return rect
    }

    private func updatePointer() {
        let inside = hotRect.contains(NSEvent.mouseLocation)
        // Click-through everywhere except the island itself, so the menu bar stays usable.
        panel.ignoresMouseEvents = !inside
        if inside {
            viewModel.pointerEntered()
        } else {
            viewModel.pointerExited()
        }
    }

    /// Re-evaluate hit testing whenever the island changes shape without the pointer moving.
    private func observeLayout() {
        withObservationTracking {
            _ = viewModel.layout
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updatePointer()
                self?.observeLayout()
            }
        }
    }
}
