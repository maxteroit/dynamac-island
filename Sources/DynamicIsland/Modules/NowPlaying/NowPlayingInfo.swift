import Foundation

struct NowPlayingInfo: Equatable, Sendable {
    var bundleIdentifier: String
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    /// Elapsed time measured at `timestamp`.
    var elapsed: TimeInterval
    var timestamp: Date
    var playbackRate: Double = 1
    var isPlaying: Bool
    var artworkData: Data?

    /// Current position, extrapolated from the last report while playing.
    func elapsed(at date: Date) -> TimeInterval {
        var value = elapsed
        if isPlaying {
            value += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        if let duration, duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }
}

/// Media keys understood by MediaRemote (IDs from mediaremote-adapter's `send`).
enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

@MainActor
protocol NowPlayingProvider: AnyObject {
    /// Called on the main actor with the latest state; nil when nothing is playing.
    var onUpdate: ((NowPlayingInfo?) -> Void)? { get set }
    func start()
    func send(_ command: MediaCommand)
    func seek(to seconds: TimeInterval)
}
