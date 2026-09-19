import AppKit

/// Puts a widget into the Dock and takes it out again, in one place.
///
/// Order matters on the way out: the spacers behind a bar are found by looking
/// right of the anchor tile, so removing the anchor first would strand them in
/// the Dock with nothing left to identify them by.
enum WidgetInstaller {
    static func install(_ widget: WidgetDescriptor) {
        DockTiles.add(widget.helperURL, restart: false)
        if wantsBar(widget) {
            DockSpacers.set(count: BarLayout.nowPlaying.spacerCount,
                            after: widget.helperURL, restart: false)
        }
        DockTiles.restartDock()
        if wantsBar(widget) { BarAgent.start() }
    }

    static func uninstall(_ widget: WidgetDescriptor) {
        DockSpacers.set(count: 0, after: widget.helperURL, restart: false)
        DockTiles.remove(widget.helperURL, restart: false)
        DockTiles.restartDock()
        if widget.id == "nowplaying" { BarAgent.stop() }
    }

    /// Switches the now-playing widget between the square tile and the wide bar.
    static func applyNowPlayingMode(_ mode: NowPlayingSettings.Mode) {
        guard let widget = WidgetCatalog.widget(id: "nowplaying") else { return }
        switch mode {
        case .tile:
            DockSpacers.set(count: 0, after: widget.helperURL, restart: false)
            DockTiles.restartDock()
            BarAgent.stop()
        case .bar:
            DockTiles.add(widget.helperURL, restart: false)
            DockSpacers.set(count: BarLayout.nowPlaying.spacerCount,
                            after: widget.helperURL, restart: false)
            DockTiles.restartDock()
            BarAgent.start()
        }
    }

    private static func wantsBar(_ widget: WidgetDescriptor) -> Bool {
        widget.id == "nowplaying" && NowPlayingSettings.current.mode == .bar
    }
}
