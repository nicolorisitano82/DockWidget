import AppKit

/// Puts a widget into the Dock and takes it out again, in one place.
///
/// Order matters on the way out: the spacers behind a bar are found by looking
/// right of the anchor tile, so removing the anchor first would strand them in
/// the Dock with nothing left to identify them by.
enum WidgetInstaller {
    static func install(_ widget: WidgetDescriptor) {
        guard widget.surface == .dock else { return }
        if let folder = widget.systemStackFolder {
            let settings = FolderSettings.current(widget.id)
            DockTiles.transaction {
                DockTiles.remove(widget)
                DockStacks.set(folder, view: settings.stackView,
                               sort: settings.stackSort, display: settings.stackDisplay)
            }
            return
        }
        DockTiles.transaction {
            DockTiles.add(widget)
            if let spec = widget.barSpec {
                DockSpacers.arrange(count: spec.spacerCount, ownedBy: widget.id, after: widget)
            }
        }
        if wantsBar(widget) { BarAgent.start() }
    }

    static func uninstall(_ widget: WidgetDescriptor) {
        if let folder = widget.systemStackFolder {
            DockTiles.transaction { DockStacks.remove(folder) }
            return
        }
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

    /// Moves a folder between our own tile and one of the Dock's stacks, and
    /// keeps the stack's own options in step while it is there.
    ///
    /// The folder the stack points at can change too, so the one that was
    /// there before is taken out by the caller, which knows what it was.
    static func applyFolderPlace(for id: String, leaving previous: URL? = nil) {
        guard let widget = WidgetCatalog.widget(id: id) else { return }
        let settings = FolderSettings.current(id)
        DockTiles.transaction {
            if let previous, previous != settings.url { DockStacks.remove(previous) }
            switch settings.place {
            case .widget:
                if let folder = settings.url { DockStacks.remove(folder) }
                DockTiles.add(widget)
            case .stack:
                guard let folder = settings.url else { return }
                DockTiles.remove(widget)
                DockStacks.set(folder, view: settings.stackView,
                               sort: settings.stackSort, display: settings.stackDisplay)
            }
        }
    }

    /// Everything the agent is needed for, in one place: the bars it draws,
    /// the notch panel it holds, and the folder previews it opens.
    static var agentIsWanted: Bool {
        NotchSettings.current.isEnabled || wantsPreviews
            || WidgetCatalog.all.contains { $0.isInstalled && $0.barSpec != nil }
    }

    static func stopAgentIfIdle() {
        // The agent draws the bars, but it also holds the notch panel and the
        // folder previews. Counting only the bars in the Dock meant that a Dock
        // with no widget in it at all took the notch down with them — and the
        // previews with it.
        if !agentIsWanted { BarAgent.stop() }
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

    /// Quitting puts the Dock back the way the user had it before Underdock.
    ///
    /// Only on a deliberate quit: doing this on logout would empty the Dock at
    /// every restart and leave it empty until the manager was opened again.
    static func uninstallAllForQuit() {
        // The agent goes first and unconditionally: it draws the bars and the
        // notch, and the notch has no tile whose absence would stop it.
        BarAgent.stop()

        let installed = WidgetCatalog.all.filter(\.isInstalled)
        SettingsStore.shared.set(installed.map(\.id), for: restoreKey)
        guard !installed.isEmpty else { return }

        DockTiles.transaction {
            for widget in installed {
                DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
                DockTiles.remove(widget)
            }
        }
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

    /// True when a folder in the Dock is set to show its preview, which is
    /// also drawn by the agent.
    static var wantsPreviews: Bool {
        WidgetCatalog.all.contains { widget in
            widget.kind == "folder" && widget.isInstalled
                && FolderSettings.current(widget.id).place == .widget
                && FolderSettings.current(widget.id).click == .preview
        }
    }

    private static func wantsBar(_ widget: WidgetDescriptor) -> Bool {
        widget.barSpec != nil
    }
}
