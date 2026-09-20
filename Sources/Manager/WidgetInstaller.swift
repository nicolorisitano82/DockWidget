import AppKit

/// Puts a widget into the Dock and takes it out again, in one place.
///
/// Order matters on the way out: the spacers behind a bar are found by looking
/// right of the anchor tile, so removing the anchor first would strand them in
/// the Dock with nothing left to identify them by.
enum WidgetInstaller {
    static func install(_ widget: WidgetDescriptor) {
        DockTiles.transaction {
            DockTiles.add(widget)
            if let spec = widget.barSpec {
                DockSpacers.arrange(count: spec.spacerCount, ownedBy: widget.id, after: widget)
            }
        }
        if wantsBar(widget) { BarAgent.start() }
    }

    static func uninstall(_ widget: WidgetDescriptor) {
        // The spacers are marked as ours, so they come out wherever the user
        // dragged them — before the tile they were anchored to goes away.
        DockTiles.transaction {
            DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
            DockTiles.remove(widget)
        }
        stopAgentIfIdle()
    }

    /// Switches a widget between its square tile and its wide bar, following
    /// whatever its own settings now say.
    static func applyBarMode(for id: String) {
        guard let widget = WidgetCatalog.widget(id: id), widget.isInstalled else { return }
        guard let spec = widget.barSpec else {
            DockTiles.transaction {
                DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
            }
            stopAgentIfIdle()
            return
        }
        DockTiles.transaction {
            DockTiles.add(widget)
            DockSpacers.arrange(count: spec.spacerCount, ownedBy: widget.id, after: widget)
        }
        BarAgent.start()
    }

    static func stopAgentIfIdle() {
        if !WidgetCatalog.all.contains(where: { $0.isInstalled && $0.barSpec != nil }) {
            BarAgent.stop()
        }
    }

    /// Switches the now-playing widget between the square tile and the wide bar.
    static func applyNowPlayingMode(_ mode: NowPlayingSettings.Mode) {
        guard let widget = WidgetCatalog.widget(id: "nowplaying") else { return }
        switch mode {
        case .tile:
            DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
            DockTiles.restartDock()
            BarAgent.stop()
        case .bar:
            DockTiles.add(widget)
            DockSpacers.arrange(count: BarLayout.nowPlaying.spacerCount,
                                ownedBy: widget.id, after: widget)
            DockTiles.restartDock()
            BarAgent.start()
        }
    }

    /// What was in the Dock when the user quit, so the next launch can put it back.
    private static let restoreKey = "session.restore"

    /// Quitting puts the Dock back the way the user had it before Dock Widgets.
    ///
    /// Only on a deliberate quit: doing this on logout would empty the Dock at
    /// every restart and leave it empty until the manager was opened again.
    static func uninstallAllForQuit() {
        let installed = WidgetCatalog.all.filter(\.isInstalled)
        SettingsStore.shared.set(installed.map(\.id), for: restoreKey)
        guard !installed.isEmpty else { return }

        DockTiles.transaction {
            for widget in installed {
                DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
                DockTiles.remove(widget)
            }
        }
        BarAgent.stop()
    }

    /// Puts back what the last quit took away.
    static func restoreAfterQuit() {
        guard let ids = SettingsStore.shared.strings(restoreKey), !ids.isEmpty else { return }
        SettingsStore.shared.set(nil, for: restoreKey)

        var wantsAgent = false
        DockTiles.transaction {
        for id in ids {
            guard let widget = WidgetCatalog.widget(id: id), !widget.isInstalled else { continue }
            DockTiles.add(widget)
            if let spec = widget.barSpec {
                DockSpacers.arrange(count: spec.spacerCount, ownedBy: widget.id, after: widget)
                wantsAgent = true
            }
        }
        }
        if wantsAgent { BarAgent.start() }
    }

    private static func wantsBar(_ widget: WidgetDescriptor) -> Bool {
        widget.barSpec != nil
    }
}
