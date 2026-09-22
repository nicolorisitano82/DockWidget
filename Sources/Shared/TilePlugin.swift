import AppKit

/// Shared plumbing for an `NSDockTilePlugIn`.
///
/// The Dock loads this bundle into `com.apple.dock.external.extra.<arch>.xpc`,
/// a process shared with every other third-party Dock extra, and it stays loaded
/// while the host app sits in the Dock — running or not. So: cheap timers, no
/// blocking work, and everything torn down when the tile goes away.
class TilePlugin: NSObject, NSDockTilePlugIn {
    /// "clock", "clock2", … read from this plug-in's own bundle identifier,
    /// which the build gives each copy of a widget.
    lazy var instanceID: String = WidgetInstance.fromBundleIdentifier(
        Bundle(for: type(of: self)).bundleIdentifier
    )

    private(set) var dockTile: NSDockTile?
    private(set) var tileView: TileView?

    private var ticker: WallClockTicker?
    private var settingsObserver: NSObjectProtocol?

    // MARK: Subclass hooks

    func makeTileView() -> TileView {
        TileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    /// Seconds between redraws. Zero means "only redraw when something changes".
    var tickInterval: TimeInterval { 0 }

    func didAttach() {}
    func willDetach() {}
    func tick() { refresh() }

    /// Widget-specific entries, shown above the standard ones.
    func customMenuItems() -> [NSMenuItem] { [] }

    // MARK: NSDockTilePlugIn

    func setDockTile(_ dockTile: NSDockTile?) {
        if let dockTile {
            attach(to: dockTile)
        } else {
            detach()
        }
    }

    /// No menu of our own.
    ///
    /// Measured rather than assumed: the Dock does ask for one — the plug-in
    /// logs the request — but choosing an item never reaches the target. The
    /// menu is handed across a process boundary and the action does not travel
    /// with it, so every item is displayed, pressed, and inert. That went for
    /// the settings item too, which looked like the one thing that could not
    /// fail.
    ///
    /// Better to leave the Dock its own menu than to offer controls that do
    /// nothing. What the menu used to promise is in the preview: click the
    /// tile and the contents are there, one click from opening, with the
    /// folder itself on the button below.
    func dockMenu() -> NSMenu? { nil }

    // MARK: Lifecycle

    /// How big the tile's own canvas is.
    ///
    /// The Dock hands the plug-in a view with no window, so it is drawn at one
    /// pixel a point — and with magnification on, the tile under the pointer
    /// reaches 128 points, which is 256 pixels on a Retina screen. At 128 the
    /// art is enlarged to fill them. Asking for more points is the one lever
    /// there is: the Dock scales what it gets down to whatever the tile is.
    static let canvas: CGFloat = 256

    private func attach(to dockTile: NSDockTile) {
        self.dockTile = dockTile
        let view = makeTileView()
        view.frame = NSRect(x: 0, y: 0, width: Self.canvas, height: Self.canvas)
        view.instance = instanceID
        view.reloadSettings()
        tileView = view
        dockTile.contentView = view

        settingsObserver = SettingsStore.shared.observeChanges { [weak self] in
            self?.tileView?.reloadSettings()
            self?.refresh()
        }

        didAttach()

        if tickInterval > 0 {
            let ticker = WallClockTicker(interval: tickInterval) { [weak self] in self?.tick() }
            ticker.start()
            self.ticker = ticker
        }
        refresh()
    }

    private func detach() {
        willDetach()
        ticker?.stop()
        ticker = nil
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
        settingsObserver = nil
        dockTile?.contentView = nil
        dockTile = nil
        tileView = nil
    }

    // MARK: Helpers

    func refresh() {
        tileView?.needsDisplay = true
        dockTile?.display()
    }

    /// `…/Host.app/Contents/PlugIns/Widget.docktileplugin` → `…/Host.app`
    var hostApplicationURL: URL? {
        let pluginURL = Bundle(for: type(of: self)).bundleURL
        let appURL = pluginURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return appURL.pathExtension == "app" ? appURL : nil
    }

    @objc private func openSettings() {
        Diagnostics.write("menu: scelta «impostazioni» da \(instanceID)")
        guard let hostApplicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: hostApplicationURL, configuration: configuration)
    }

    func menuItem(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: enabled ? selector : nil, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }
}
