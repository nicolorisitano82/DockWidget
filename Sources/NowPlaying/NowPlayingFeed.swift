import AppKit

/// The bridge between the one process that can read MediaRemote and the ones
/// that cannot.
///
/// Only the Dock's plug-in host gets an answer from the now-playing registry,
/// so the plug-in publishes what it sees into the user's cache directory and
/// posts a notification; the manager window and the overlay agent read it back.
/// Commands travel the other way, as a notification the plug-in executes.
enum NowPlayingFeed {
    static let stateChanged = Notification.Name("dev.nicolo.dockwidgets.nowPlayingChanged")
    static let commandRequested = Notification.Name("dev.nicolo.dockwidgets.nowPlayingCommand")

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/dev.nicolo.dockwidgets", isDirectory: true)
    }

    static var stateURL: URL { directory.appendingPathComponent("nowplaying.json") }

    // MARK: Publishing (plug-in side)

    static func publish(_ state: NowPlayingState) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var payload: [String: Any] = [
            "isPlaying": state.isPlaying,
            "sampledAt": state.elapsedSampledAt.timeIntervalSince1970,
            "updatedAt": Date().timeIntervalSince1970,
            "origin": state.origin.rawValue,
        ]
        payload["title"] = state.title
        payload["artist"] = state.artist
        payload["album"] = state.album
        payload["elapsed"] = state.elapsed
        payload["duration"] = state.duration
        payload["playerBundleID"] = state.playerBundleID

        // Artwork travels as the player published it — no re-encoding inside
        // the Dock's process — under a name derived from its own identifier, so
        // a reader can skip a cover it already loaded.
        if let data = state.artworkData {
            // MediaRemote's identifiers carry '#' and ':' — keep the name plain.
            let identifier = (state.artworkIdentifier ?? String(data.count))
                .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            let name = "artwork-\(String(identifier).prefix(64)).bin"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url)
                pruneArtwork(keeping: name)
            }
            payload["artworkFile"] = name
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: stateURL, options: .atomic)
        DistributedNotificationCenter.default().postNotificationName(
            stateChanged, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private static func pruneArtwork(keeping name: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasPrefix("artwork-") && file != name {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: Reading (manager and agent side)

    static func read() -> NowPlayingState? {
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var state = NowPlayingState()
        state.origin = .published
        state.title = payload["title"] as? String
        state.artist = payload["artist"] as? String
        state.album = payload["album"] as? String
        state.isPlaying = payload["isPlaying"] as? Bool ?? false
        state.elapsed = payload["elapsed"] as? Double
        state.duration = payload["duration"] as? Double
        state.playerBundleID = payload["playerBundleID"] as? String
        if let sampledAt = payload["sampledAt"] as? Double {
            state.elapsedSampledAt = Date(timeIntervalSince1970: sampledAt)
        }
        if let file = payload["artworkFile"] as? String {
            state.artwork = NSImage(contentsOf: directory.appendingPathComponent(file))
        }
        return state
    }

    static func observe(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: stateChanged, object: nil, queue: .main
        ) { _ in handler() }
    }

    // MARK: Commands

    enum Command {
        case togglePlayPause
        case next
        case previous
        case seek(TimeInterval)

        /// Commands travel as the notification's object, so they are a string.
        var wire: String {
            switch self {
            case .togglePlayPause: return "togglePlayPause"
            case .next: return "next"
            case .previous: return "previous"
            case .seek(let seconds): return "seek:\(seconds)"
            }
        }

        init?(wire: String) {
            if wire.hasPrefix("seek:"), let seconds = TimeInterval(wire.dropFirst(5)) {
                self = .seek(seconds)
                return
            }
            switch wire {
            case "togglePlayPause": self = .togglePlayPause
            case "next": self = .next
            case "previous": self = .previous
            default: return nil
            }
        }
    }

    /// Asks the privileged reader to run a transport command.
    static func send(_ command: Command) {
        DistributedNotificationCenter.default().postNotificationName(
            commandRequested, object: command.wire, userInfo: nil, deliverImmediately: true
        )
    }

    static func observeCommands(_ handler: @escaping (Command) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: commandRequested, object: nil, queue: .main
        ) { note in
            guard let raw = note.object as? String, let command = Command(wire: raw) else { return }
            handler(command)
        }
    }
}
