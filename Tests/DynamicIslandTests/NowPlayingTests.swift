import Foundation
import Testing
@testable import DynamicIsland

struct AdapterStreamTests {
    let full: [String: Any] = [
        "bundleIdentifier": "com.spotify.client",
        "title": "Song",
        "artist": "Artist",
        "playing": true,
        "durationMicros": 200_000_000,
        "elapsedTimeMicros": 30_000_000,
        "timestampEpochMicros": 1_000_000_000_000_000,
        "playbackRate": 1,
    ]

    @Test func parsesMicrosPayload() throws {
        let info = try #require(AdapterStreamReader.info(from: full))
        #expect(info.title == "Song")
        #expect(info.duration == 200)
        #expect(info.elapsed == 30)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_000_000_000))
        #expect(info.isPlaying)
    }

    @Test func emptyArtistAndAlbumBecomeNil() throws {
        var state = full
        state["artist"] = ""
        state["album"] = ""
        let info = try #require(AdapterStreamReader.info(from: state))
        #expect(info.artist == nil)
        #expect(info.album == nil)
    }

    @Test func missingMandatoryKeyMeansNothingPlaying() {
        var state = full
        state["title"] = nil
        #expect(AdapterStreamReader.info(from: state) == nil)
        #expect(AdapterStreamReader.info(from: [:]) == nil)
    }

    @Test func diffUpdatesAndNullRemoves() {
        let merged = AdapterStreamReader.merge(full, payload: ["playing": false, "artist": NSNull()], diff: true)
        #expect(merged["playing"] as? Bool == false)
        #expect(merged["artist"] == nil)
        #expect(merged["title"] as? String == "Song")
    }

    @Test func nonDiffReplacesState() {
        let merged = AdapterStreamReader.merge(full, payload: ["title": "Other"], diff: false)
        #expect(merged.count == 1)
    }

    @Test func readerHandlesLinesSplitAcrossChunks() async {
        let received = Received()
        let reader = AdapterStreamReader { info in received.append(info) }
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"T","playing":true}}"# + "\n"
        let bytes = Data(line.utf8)
        reader.consume(bytes.prefix(20))
        #expect(received.values.isEmpty)
        reader.consume(bytes.dropFirst(20))
        #expect(received.values.count == 1)
        #expect(received.values.first??.title == "T")
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [NowPlayingInfo?] = []
    var values: [NowPlayingInfo?] { lock.withLock { storage } }
    func append(_ info: NowPlayingInfo?) { lock.withLock { storage.append(info) } }
}

struct NowPlayingInfoTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func info(playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(bundleIdentifier: "x", title: "t", duration: 100, elapsed: 10,
                       timestamp: start, isPlaying: playing)
    }

    @Test func extrapolatesWhilePlayingAndClampsToDuration() {
        #expect(info(playing: true).elapsed(at: start + 5) == 15)
        #expect(info(playing: true).elapsed(at: start + 500) == 100)
    }

    @Test func pausedPositionStaysPut() {
        #expect(info(playing: false).elapsed(at: start + 50) == 10)
    }

    @Test func spotifyNotificationParsing() throws {
        let spotify = PlayerNotificationProvider.players[0]
        let parsed = try #require(PlayerNotificationProvider.info(
            from: ["Player State": "Paused", "Name": "Song", "Artist": "A", "Duration": 180_000, "Playback Position": 42.5],
            player: spotify, now: start
        ))
        #expect(parsed.duration == 180)
        #expect(parsed.elapsed == 42.5)
        #expect(!parsed.isPlaying)
        #expect(PlayerNotificationProvider.info(from: ["Player State": "Stopped", "Name": "x"], player: spotify, now: start) == nil)
    }
}
