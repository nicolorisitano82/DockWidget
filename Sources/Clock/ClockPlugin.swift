import AppKit

@objc(ClockDockTilePlugin)
final class ClockDockTilePlugin: TilePlugin {
    private var clockView: ClockTileView? { tileView as? ClockTileView }
    private var lastToken = Int.min

    override func makeTileView() -> TileView {
        ClockTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    /// One tick a second, but a redraw only when the face would actually change:
    /// with seconds off, that is once a minute.
    override var tickInterval: TimeInterval { 1 }

    override func tick() {
        guard let clockView else { return }
        let token = clockView.renderToken()
        guard token != lastToken else { return }
        lastToken = token
        refresh()
    }

    override func customMenuItems() -> [NSMenuItem] {
        [
            menuItem(T("Copia l'ora", "Copy the time"), #selector(copyTime)),
            menuItem(T("Apri Calendario", "Open Calendar"), #selector(openCalendar)),
        ]
    }

    @objc private func copyTime() {
        guard let clockView else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clockView.formattedTime, forType: .string)
    }

    @objc private func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
