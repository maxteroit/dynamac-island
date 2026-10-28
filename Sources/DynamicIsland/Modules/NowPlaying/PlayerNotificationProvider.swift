import AppKit

/// Fallback when the adapter is missing: Spotify and Music broadcast their state
/// as distributed notifications (no permission needed). Controls use AppleScript,
/// which triggers the Automation permission prompt on first use.
/// No artwork and no browser playback.
@MainActor
final class PlayerNotificationProvider: NSObject, NowPlayingProvider {
    struct Player: Sendable {
        let bundleIdentifier: String
        let notification: String
        let scriptName: String
        /// Spotify reports duration in milliseconds, Music in "Total Time" milliseconds.
        let durationKey: String
    }

    nonisolated static let players = [
        Player(bundleIdentifier: "com.spotify.client", notification: "com.spotify.client.PlaybackStateChanged",
               scriptName: "Spotify", durationKey: "Duration"),
        Player(bundleIdentifier: "com.apple.Music", notification: "com.apple.Music.playerInfo",
               scriptName: "Music", durationKey: "Total Time"),
    ]

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    private var current: (player: Player, info: NowPlayingInfo)?

    func start() {
        for player in Self.players {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(playerChanged(_:)),
                name: Notification.Name(player.notification),
                object: nil
            )
        }
    }

    @objc private func playerChanged(_ notification: Notification) {
        guard let player = Self.players.first(where: { $0.notification == notification.name.rawValue }) else { return }
        let info = Self.info(from: notification.userInfo ?? [:], player: player, now: .now)
        if let info {
            current = (player, info)
        } else if current?.player.bundleIdentifier == player.bundleIdentifier {
            current = nil
        }
        onUpdate?(current?.info)
    }

    nonisolated static func info(from userInfo: [AnyHashable: Any], player: Player, now: Date) -> NowPlayingInfo? {
        guard let state = userInfo["Player State"] as? String, state != "Stopped",
              let title = userInfo["Name"] as? String
        else { return nil }
        let durationMillis = (userInfo[player.durationKey] as? NSNumber)?.doubleValue
        return NowPlayingInfo(
            bundleIdentifier: player.bundleIdentifier,
            title: title,
            artist: userInfo["Artist"] as? String,
            album: userInfo["Album"] as? String,
            duration: durationMillis.map { $0 / 1000 },
            elapsed: (userInfo["Playback Position"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: now,
            isPlaying: state == "Playing"
        )
    }

    func send(_ command: MediaCommand) {
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        runScript(verb)
    }

    func seek(to seconds: TimeInterval) {
        runScript("set player position to \(max(0, seconds))")
    }

    private func runScript(_ command: String) {
        guard let player = current?.player else { return }
        let source = "tell application \"\(player.scriptName)\" to \(command)"
        NSAppleScript(source: source)?.executeAndReturnError(nil)
    }
}
