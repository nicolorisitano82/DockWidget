import AppKit

@objc(SensorsDockTilePlugin)
final class SensorsDockTilePlugin: TilePlugin {
    private var sensorsView: SensorsTileView? { tileView as? SensorsTileView }
    private var token: UUID?
    private var lastToken = ""

    override func makeTileView() -> TileView {
        SensorsTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func didAttach() {
        // Driven by the sampler rather than by a clock of its own: the tile is
        // redrawn when a reading changes, not on a beat that might not line up
        // with it.
        token = SensorSampler.shared.addListener(for: Set(SensorID.allCases)) { [weak self] in
            guard let self, let view = self.sensorsView else { return }
            let current = view.renderToken
            guard current != self.lastToken else { return }
            self.lastToken = current
            self.refresh()
        }
    }

    override func willDetach() {
        if let token { SensorSampler.shared.removeListener(token) }
        token = nil
    }

    override func customMenuItems() -> [NSMenuItem] {
        let reading = SensorSampler.shared.reading(SensorsSettings.current.tileSensor)
        let item = NSMenuItem(title: "\(SensorsSettings.current.tileSensor.label): \(reading.text)",
                              action: nil, keyEquivalent: "")
        item.isEnabled = false
        return [item]
    }
}
