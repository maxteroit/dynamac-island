import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Set before `level`: `isFloatingPanel` resets the level to `.floating`,
        // where macOS pushes the window below the menu bar.
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    // Key status lets buttons and sliders inside the expanded island work.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The island lives in the menu bar / notch area; never let AppKit move it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reacts to the first click even while the app is inactive.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Container that reports pointer movement while the panel accepts mouse events.
/// The global monitor in `IslandWindowController` covers the click-through case.
final class TrackingContainerView: NSView {
    var onPointerMove: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { onPointerMove?() }
    override func mouseEntered(with event: NSEvent) { onPointerMove?() }
    override func mouseExited(with event: NSEvent) { onPointerMove?() }
}
