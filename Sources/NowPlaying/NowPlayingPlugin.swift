import AppKit

@objc(NowPlayingDockTilePlugin)
final class NowPlayingDockTilePlugin: TilePlugin {
    private var nowPlayingView: NowPlayingTileView? { tileView as? NowPlayingTileView }
    private var lastToken = ""
    private var listenerToken: UUID?

    override func makeTileView() -> TileView {
        NowPlayingTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    /// Once a second, to walk the progress bar forward. Everything else is
    /// driven by notifications.
    override var tickInterval: TimeInterval { 1 }

    override func didAttach() {
        listenerToken = NowPlayingSource.shared.addListener { [weak self] state in
            self?.apply(state)
        }
    }

    override func willDetach() {
        if let listenerToken {
            NowPlayingSource.shared.removeListener(listenerToken)
        }
        listenerToken = nil
    }

    override func tick() {
        guard let nowPlayingView else { return }
        let token = nowPlayingView.state.renderToken()
        guard token != lastToken else { return }
        lastToken = token
        refresh()
    }

    private func apply(_ state: NowPlayingState) {
        nowPlayingView?.state = state
        lastToken = state.renderToken()
        refresh()
    }

    override func customMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let state = NowPlayingSource.shared.state

        if state.hasTrack {
            let title = NSMenuItem(title: state.title ?? "", action: nil, keyEquivalent: "")
            title.isEnabled = false
            items.append(title)
            if let subtitle = state.subtitle {
                let item = NSMenuItem(title: subtitle, action: nil, keyEquivalent: "")
                item.isEnabled = false
                items.append(item)
            }
            items.append(.separator())
        }

        let canControl = MediaRemoteBridge.shared.canSendCommands && NowPlayingSource.shared.mediaRemoteAnswered
        if canControl {
            items.append(menuItem(state.isPlaying ? "Pausa" : "Riproduci", #selector(togglePlayPause)))
            items.append(menuItem("Brano successivo", #selector(nextTrack)))
            items.append(menuItem("Brano precedente", #selector(previousTrack)))
        } else {
            let note = NSMenuItem(title: "Controlli non disponibili", action: nil, keyEquivalent: "")
            note.isEnabled = false
            items.append(note)
        }

        if let bundleID = state.playerBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            items.append(menuItem("Apri \(name)", #selector(openPlayer)))
        }
        return items
    }

    @objc private func togglePlayPause() {
        MediaRemoteBridge.shared.send(.togglePlayPause)
        NowPlayingSource.shared.refreshFromMediaRemote()
    }

    @objc private func nextTrack() {
        MediaRemoteBridge.shared.send(.next)
    }

    @objc private func previousTrack() {
        MediaRemoteBridge.shared.send(.previous)
    }

    @objc private func openPlayer() {
        guard let bundleID = NowPlayingSource.shared.state.playerBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
