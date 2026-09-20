import AppKit

/// Feeds every consumer from whichever channel this process is allowed to use.
///
/// Three channels, best first:
/// 1. **MediaRemote** — only answers inside the Dock's plug-in host. Full
///    metadata, artwork and transport control. When we are that process, we
///    also republish everything for the others and take their commands.
/// 2. **The published feed** — what the plug-in wrote. This is how the manager
///    window and the overlay agent see a cover at all.
/// 3. **Music and Spotify broadcasts** — no permission, no artwork, no control.
final class NowPlayingSource {
    static let shared = NowPlayingSource()

    private(set) var state = NowPlayingState()
    private(set) var mediaRemoteAnswered = false

    private var listeners: [UUID: (NowPlayingState) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var resyncTimer: Timer?
    private var started = false
    private var owningChannel: NowPlayingState.Origin = .none
    private var loggedChannel: NowPlayingState.Origin?
    private var lastUpdate = Date.distantPast

    private static let broadcasts: [(name: String, bundleID: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.apple.iTunes.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    /// Registers a listener, starting the channels on the first one.
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

    // MARK: Channels

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

            // Notifications do get missed when a player restarts, and a stuck
            // progress bar is the visible symptom.
            // Always, not only while something plays: the published state has
            // to keep saying "still true" or the readers will stop believing it.
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                guard let self, self.mediaRemoteAnswered else { return }
                self.refreshFromMediaRemote()
            }
            RunLoop.main.add(timer, forMode: .common)
            resyncTimer = timer
        }

        let feedObserver = NowPlayingFeed.observe { [weak self] in self?.adoptPublishedState() }
        distributedObservers.append(feedObserver)
        adoptPublishedState()

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
                // An empty answer means "nothing playing" only if this process is
                // the one MediaRemote talks to; otherwise it means "not you".
                if self.mediaRemoteAnswered {
                    self.publish(NowPlayingState(), from: .mediaRemote)
                }
                return
            }
            if !self.mediaRemoteAnswered {
                self.mediaRemoteAnswered = true
                self.startServingCommands()
            }
            MediaRemoteBridge.shared.readIsPlaying { isPlaying in
                fetched.isPlaying = isPlaying
                self.publish(fetched, from: .mediaRemote)
            }
        }
    }

    /// Only the privileged reader runs this: it answers the commands the
    /// overlay and the manager cannot send themselves.
    private func startServingCommands() {
        let token = NowPlayingFeed.observeCommands { [weak self] command in
            let bridge = MediaRemoteBridge.shared
            switch command {
            case .togglePlayPause: bridge.send(.togglePlayPause)
            case .next: bridge.send(.next)
            case .previous: bridge.send(.previous)
            case .seek(let seconds): bridge.setElapsedTime(seconds)
            }
            // The registry takes a moment to settle after a command.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.refreshFromMediaRemote()
            }
        }
        distributedObservers.append(token)
        Diagnostics.write("servo i comandi di riproduzione per gli altri processi")
    }

    private func adoptPublishedState() {
        guard !mediaRemoteAnswered, let published = NowPlayingFeed.read() else { return }
        publish(published, from: .published)
    }

    private func handleBroadcast(_ note: Notification, bundleID: String) {
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
        publish(next, from: .broadcast)
    }

    private func playerIcon(for bundleID: String) -> NSImage? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Publishing

    private func rank(_ origin: NowPlayingState.Origin) -> Int {
        switch origin {
        case .mediaRemote: return 3
        case .published: return 2
        case .broadcast: return 1
        case .none: return 0
        }
    }

    private func publish(_ next: NowPlayingState, from channel: NowPlayingState.Origin) {
        // A weaker channel never overwrites a stronger one — unless the
        // stronger one has gone quiet. A reader that stopped running leaves its
        // last answer behind, and that answer ages into a lie.
        let wentQuiet = Date().timeIntervalSince(lastUpdate) > 20
        guard rank(channel) >= rank(owningChannel) || wentQuiet else { return }
        owningChannel = channel
        lastUpdate = Date()
        state = next
        logChannel(channel)

        if channel == .mediaRemote {
            NowPlayingFeed.publish(next)
        }
        for listener in listeners.values {
            listener(next)
        }
    }

    private func logChannel(_ origin: NowPlayingState.Origin) {
        guard loggedChannel != origin else { return }
        loggedChannel = origin
        Diagnostics.write("canale now playing: \(origin.rawValue)")
    }
}
