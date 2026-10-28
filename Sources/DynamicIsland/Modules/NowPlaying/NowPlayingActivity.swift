import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NowPlayingActivity: LiveActivity {
    let id = "nowPlaying"
    let priority = ActivityPriority.normal
    /// Only the spectrum, right of the notch, so app menus on the left stay visible.
    let compactStyle = CompactStyle.trailingOnly
    private(set) var activatedAt: Date?
    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    private(set) var accentColor: Color = .white
    /// Lets the progress bar follow a scrub before the player confirms the new position.
    private(set) var pendingSeek: TimeInterval?

    /// Hide from the compact island this long after pausing. Hovering the notch
    /// still opens the player so playback can be resumed.
    static let pausedGrace: Duration = .seconds(5)

    var offersExpandedWhileInactive: Bool { info != nil }

    @ObservationIgnored private let provider: any NowPlayingProvider
    @ObservationIgnored private var graceTask: Task<Void, Never>?

    init(provider: any NowPlayingProvider) {
        self.provider = provider
        provider.onUpdate = { [weak self] info in self?.update(info) }
        provider.start()
    }

    /// Picks the adapter when it is bundled, otherwise the Spotify/Music fallback.
    static func makeDefault() -> NowPlayingActivity {
        if let paths = MediaRemoteAdapterProvider.Paths.bundled() {
            return NowPlayingActivity(provider: MediaRemoteAdapterProvider(paths: paths))
        }
        return NowPlayingActivity(provider: PlayerNotificationProvider())
    }

    var appIcon: NSImage? {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Controls

    func togglePlayPause() {
        info?.isPlaying.toggle()
        provider.send(.togglePlayPause)
    }

    func nextTrack() { provider.send(.nextTrack) }
    func previousTrack() { provider.send(.previousTrack) }

    func seek(to seconds: TimeInterval) {
        pendingSeek = seconds
        provider.seek(to: seconds)
    }

    func elapsed(at date: Date) -> TimeInterval {
        pendingSeek ?? info?.elapsed(at: date) ?? 0
    }

    // MARK: - Updates

    private func update(_ new: NowPlayingInfo?) {
        let old = info
        if new?.artworkData != old?.artworkData || new?.bundleIdentifier != old?.bundleIdentifier {
            artwork = new?.artworkData.flatMap(NSImage.init(data:))
            accentColor = artwork.map { Color(nsColor: $0.averageColor.brightenedForDarkBackground) } ?? .white
        }
        if new?.elapsed != old?.elapsed || new?.timestamp != old?.timestamp {
            pendingSeek = nil
        }
        info = new

        switch new {
        case let new? where new.isPlaying:
            graceTask?.cancel()
            graceTask = nil
            if activatedAt == nil {
                withAnimation(.islandExpand) { activatedAt = .now }
            }
        case .some:
            schedulePausedGrace()
        case nil:
            graceTask?.cancel()
            graceTask = nil
            withAnimation(.islandCollapse) { activatedAt = nil }
        }
    }

    private func schedulePausedGrace() {
        guard activatedAt != nil, graceTask == nil else { return }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pausedGrace)
            guard let self, !Task.isCancelled else { return }
            self.graceTask = nil
            withAnimation(.islandCollapse) { self.activatedAt = nil }
        }
    }

    // MARK: - LiveActivity

    func compactLeading() -> AnyView {
        AnyView(ArtworkView(activity: self, size: 20, cornerRadius: 5))
    }

    func compactTrailing() -> AnyView {
        AnyView(PlaybackIndicator(activity: self).frame(width: 22, height: 14))
    }

    func minimal() -> AnyView {
        AnyView(ArtworkView(activity: self, size: 20, cornerRadius: 10))
    }

    func expanded() -> AnyView {
        AnyView(NowPlayingExpandedView(activity: self))
    }
}

private extension NSImage {
    /// Average color, computed by drawing the image into a single pixel.
    var averageColor: NSColor {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ) else { return .white }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .medium
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: 0, y: 0) ?? .white
    }
}

private extension NSColor {
    /// Keeps the accent readable on the black island.
    var brightenedForDarkBackground: NSColor {
        guard let hsb = usingColorSpace(.deviceRGB) else { return self }
        return NSColor(
            hue: hsb.hueComponent,
            saturation: min(hsb.saturationComponent, 0.8),
            brightness: max(hsb.brightnessComponent, 0.75),
            alpha: 1
        )
    }
}
