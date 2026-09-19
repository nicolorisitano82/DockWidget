import AppKit

/// Feeds the tile from whichever channel this process is actually allowed to use.
///
/// 1. MediaRemote, if it answers — every player, artwork, position, transport control.
/// 2. Otherwise the playback broadcasts Music and Spotify post to every process:
///    no permission prompt, but title/artist only and no control.
final class NowPlayingSource {
    static let shared = NowPlayingSource()

    private(set) var state = NowPlayingState()
    private(set) var mediaRemoteAnswered = false

    private var listeners: [UUID: (NowPlayingState) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var resyncTimer: Timer?
    private var loggedChannel: NowPlayingState.Origin?
    private var started = false

    private static let broadcasts: [(name: String, bundleID: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.apple.iTunes.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    /// Registers a listener, starting the channels on the first one.
    /// The host window and the Dock plug-in both watch the same source.
    @discardableResult
    func addListener(_ handler: @escaping (NowPlayingState) -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        start()
        handler(state)
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty { stop() }
    }

    private func start() {
        guard !started else { return }
        started = true

        let bridge = MediaRemoteBridge.shared
        if bridge.isLinked {
            bridge.registerForNotifications()
            for name in [MediaRemoteBridge.infoDidChange, MediaRemoteBridge.isPlayingDidChange] {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refreshFromMediaRemote()
                }
                observers.append(token)
            }
            refreshFromMediaRemote()

            // A cheap safety net: notifications do get missed when a player
            // restarts, and a stuck progress bar is the visible symptom.
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                guard let self, self.mediaRemoteAnswered, self.state.isPlaying else { return }
                self.refreshFromMediaRemote()
            }
            RunLoop.main.add(timer, forMode: .common)
            resyncTimer = timer
        }

        for broadcast in Self.broadcasts {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(broadcast.name), object: nil, queue: .main
            ) { [weak self] note in
                self?.handleBroadcast(note, bundleID: broadcast.bundleID)
            }
            distributedObservers.append(token)
        }
    }

    private func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        distributedObservers.removeAll()
        resyncTimer?.invalidate()
        resyncTimer = nil
        started = false
    }

    func refreshFromMediaRemote() {
        MediaRemoteBridge.shared.readNowPlaying { [weak self] fetched in
            guard let self else { return }
            guard var fetched else {
                // Empty answer: either nothing is playing or we are not trusted.
                // Only clear the tile if MediaRemote is the channel we are on.
                if self.mediaRemoteAnswered, self.state.origin == .mediaRemote {
                    self.publish(NowPlayingState())
                }
                return
            }
            self.mediaRemoteAnswered = true
            MediaRemoteBridge.shared.readIsPlaying { isPlaying in
                fetched.isPlaying = isPlaying
                self.publish(fetched)
            }
        }
    }

    private func handleBroadcast(_ note: Notification, bundleID: String) {
        // MediaRemote wins when it works: it knows about every player, not just this one.
        guard !mediaRemoteAnswered else { return }
        guard let info = note.userInfo else { return }

        var next = NowPlayingState()
        next.origin = .broadcast
        next.playerBundleID = bundleID
        next.title = info["Name"] as? String
        next.artist = info["Artist"] as? String
        next.album = info["Album"] as? String
        next.isPlaying = (info["Player State"] as? String) == "Playing"

        if let milliseconds = (info["Total Time"] as? NSNumber)?.doubleValue {
            next.duration = milliseconds / 1000
        } else if let milliseconds = (info["Duration"] as? NSNumber)?.doubleValue {
            next.duration = milliseconds / 1000
        }
        if let position = (info["Playback Position"] as? NSNumber)?.doubleValue {
            next.elapsed = position
            next.elapsedSampledAt = Date()
        } else if next.title != state.title {
            // Music does not report a position. A new title means a new track,
            // so start counting from zero; a pause/resume keeps what we had.
            next.elapsed = 0
            next.elapsedSampledAt = Date()
        } else {
            next.elapsed = state.elapsed
            next.elapsedSampledAt = state.elapsedSampledAt
        }
        next.artwork = playerIcon(for: bundleID)
        publish(next)
    }

    private func playerIcon(for bundleID: String) -> NSImage? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// One line per channel change, so which channel answered can be read back
    /// from the system log — the plug-in has no other way to report.
    private func logChannel(_ origin: NowPlayingState.Origin) {
        guard loggedChannel != origin else { return }
        loggedChannel = origin
        NSLog("[dockwidgets] canale now playing: %@", origin.rawValue)
    }

    private func publish(_ next: NowPlayingState) {
        logChannel(next.origin)
        state = next
        for listener in listeners.values {
            listener(next)
        }
    }
}
