import AppKit

/// Shared plumbing for an `NSDockTilePlugIn`.
///
/// The Dock loads this bundle into `com.apple.dock.external.extra.<arch>.xpc`,
/// a process shared with every other third-party Dock extra, and it stays loaded
/// while the host app sits in the Dock — running or not. So: cheap timers, no
/// blocking work, and everything torn down when the tile goes away.
class TilePlugin: NSObject, NSDockTilePlugIn {
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

    func dockMenu() -> NSMenu? {
        let menu = NSMenu()
        for item in customMenuItems() {
            menu.addItem(item)
        }
        if menu.numberOfItems > 0 {
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "Impostazioni…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    // MARK: Lifecycle

    private func attach(to dockTile: NSDockTile) {
        self.dockTile = dockTile
        let view = makeTileView()
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
