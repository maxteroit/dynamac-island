import Foundation
import OSLog

/// Reads system-wide Now Playing through mediaremote-adapter. Since macOS 15.4
/// MediaRemote only answers entitled processes; the adapter runs inside
/// `/usr/bin/perl`, which is entitled, and streams JSON lines to stdout.
@MainActor
final class MediaRemoteAdapterProvider: NowPlayingProvider {
    struct Paths {
        let script: URL
        let framework: URL

        /// Locations inside the .app bundle, as laid out by scripts/build-app.sh.
        static func bundled(in bundle: Bundle = .main) -> Paths? {
            guard let resources = bundle.resourceURL, let frameworks = bundle.privateFrameworksURL else { return nil }
            let paths = Paths(
                script: resources.appendingPathComponent("mediaremote-adapter.pl"),
                framework: frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
            )
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: paths.script.path),
                  fileManager.fileExists(atPath: paths.framework.path) else { return nil }
            return paths
        }
    }

    var onUpdate: ((NowPlayingInfo?) -> Void)?

    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "NowPlaying")
    private let paths: Paths
    private var process: Process?
    private var restartAttempts = 0
    private static let maxRestartAttempts = 5

    init(paths: Paths) {
        self.paths = paths
    }

    func start() {
        guard process == nil else { return }
        let process = makeProcess(arguments: ["stream", "--micros", "--debounce=100"])
        let pipe = Pipe()
        process.standardOutput = pipe

        let reader = AdapterStreamReader { [weak self] info in
            Task { @MainActor in
                self?.restartAttempts = 0
                self?.onUpdate?(info)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.consume(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.streamTerminated(status: status) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            logger.error("Failed to launch adapter: \(error.localizedDescription, privacy: .public)")
        }
    }

    func send(_ command: MediaCommand) {
        runOnce(["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        runOnce(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    private func streamTerminated(status: Int32) {
        process = nil
        onUpdate?(nil)
        guard restartAttempts < Self.maxRestartAttempts else {
            logger.error("Adapter keeps exiting (status \(status)); giving up")
            return
        }
        restartAttempts += 1
        let delay = Duration.seconds(restartAttempts * 2)
        logger.warning("Adapter exited (status \(status)); restarting in \(delay.description, privacy: .public)")
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.start()
        }
    }

    private func runOnce(_ arguments: [String]) {
        let process = makeProcess(arguments: arguments)
        process.standardOutput = FileHandle.nullDevice
        try? process.run()
    }

    private func makeProcess(arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }
}

/// Splits the adapter's stdout into JSON lines, merges diffs, and emits full states.
/// Runs on the pipe's background queue.
final class AdapterStreamReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private let emit: @Sendable (NowPlayingInfo?) -> Void

    init(emit: @escaping @Sendable (NowPlayingInfo?) -> Void) {
        self.emit = emit
    }

    func consume(_ data: Data) {
        let infos: [NowPlayingInfo?] = lock.withLock {
            buffer.append(data)
            var results: [NowPlayingInfo?] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = message["payload"] as? [String: Any]
                else { continue }
                state = Self.merge(state, payload: payload, diff: message["diff"] as? Bool ?? false)
                results.append(Self.info(from: state))
            }
            return results
        }
        infos.forEach(emit)
    }

    /// Applies a stream payload. Diffs update keys in place; `null` removes a key.
    static func merge(_ state: [String: Any], payload: [String: Any], diff: Bool) -> [String: Any] {
        var merged = diff ? state : [:]
        for (key, value) in payload {
            merged[key] = value is NSNull ? nil : value
        }
        return merged
    }

    /// Parses a full adapter state produced with `--micros`.
    static func info(from state: [String: Any]) -> NowPlayingInfo? {
        guard let bundleIdentifier = state["bundleIdentifier"] as? String,
              let title = state["title"] as? String,
              let isPlaying = state["playing"] as? Bool
        else { return nil }

        func text(_ key: String) -> String? {
            (state[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        func seconds(_ key: String) -> TimeInterval? {
            (state[key] as? NSNumber).map { $0.doubleValue / 1_000_000 }
        }

        return NowPlayingInfo(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: text("artist"),
            album: text("album"),
            duration: seconds("durationMicros"),
            elapsed: seconds("elapsedTimeMicros") ?? 0,
            timestamp: seconds("timestampEpochMicros").map(Date.init(timeIntervalSince1970:)) ?? .now,
            playbackRate: (state["playbackRate"] as? NSNumber)?.doubleValue ?? 1,
            isPlaying: isPlaying,
            artworkData: (state["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        )
    }
}
