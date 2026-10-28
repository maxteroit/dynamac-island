import AppKit

enum NotchGeometry {
    /// Used on screens without a notch (external displays, older Macs).
    static let fallbackWidth: CGFloat = 185
    static let fallbackHeight: CGFloat = 24

    /// Physical notch size in points. The notch is the gap between the two
    /// auxiliary top areas that macOS reserves for menu bar content.
    static func notchSize(
        screenWidth: CGFloat,
        leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?,
        safeAreaTop: CGFloat,
        menuBarHeight: CGFloat
    ) -> CGSize {
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth {
            let width = screenWidth - left - right
            if width > 0 {
                return CGSize(width: width, height: safeAreaTop)
            }
        }
        return CGSize(width: fallbackWidth, height: menuBarHeight > 0 ? menuBarHeight : fallbackHeight)
    }
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    /// Zero when the menu bar is set to auto-hide.
    var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }

    var notchSize: CGSize {
        NotchGeometry.notchSize(
            screenWidth: frame.width,
            leftAreaWidth: auxiliaryTopLeftArea?.width,
            rightAreaWidth: auxiliaryTopRightArea?.width,
            safeAreaTop: safeAreaInsets.top,
            menuBarHeight: menuBarHeight
        )
    }

    /// Built-in notched display first, otherwise the main display.
    static var preferredIslandScreen: NSScreen? {
        screens.first(where: \.hasNotch) ?? main ?? screens.first
    }
}
