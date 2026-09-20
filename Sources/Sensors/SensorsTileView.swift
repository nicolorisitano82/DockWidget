import AppKit

/// One sensor, filling a square Dock tile: a ring with the number inside.
final class SensorsTileView: TileView {
    private var settings = SensorsSettings.current
    private var token: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        subscribe()
    }

    deinit {
        if let token { SensorSampler.shared.removeListener(token) }
    }

    override func reloadSettings() {
        settings = SensorsSettings.current
        accent = settings.accent
        subscribe()
        needsDisplay = true
    }

    private func subscribe() {
        if let token { SensorSampler.shared.removeListener(token) }
        SensorSampler.shared.setInterval(settings.refresh)
        token = SensorSampler.shared.addListener(for: [settings.tileSensor]) { [weak self] in
            self?.needsDisplay = true
        }
    }

    /// What the tile shows now, so a plug-in can skip a redraw that would paint
    /// the same pixels.
    var renderToken: String {
        let reading = SensorSampler.shared.reading(settings.tileSensor)
        return "\(settings.tileSensor.rawValue)|\(reading.text)|\(Int((reading.fraction ?? 0) * 100))"
    }

    override func draw(_ dirtyRect: NSRect) {
        // In bar mode the tile is only an anchor for the overlay above it.
        guard settings.mode == .tile else { return }
        let card = drawCard()
        let palette = self.palette
        let side = card.width
        let reading = SensorSampler.shared.reading(settings.tileSensor)

        let ringBox = card.insetBy(dx: side * 0.14, dy: side * 0.14)
        if let fraction = reading.fraction {
            SensorGauge.ring(in: ringBox, fraction: fraction, width: side * 0.085,
                             color: palette.accent, track: SensorGauge.trackColor())
        } else if settings.showsSparkline {
            let line = NSRect(x: card.minX + side * 0.16, y: card.midY - side * 0.30,
                              width: card.width - side * 0.32, height: side * 0.22)
            SensorGauge.sparkline(in: line, samples: SensorSampler.shared.trend(settings.tileSensor),
                                  color: palette.accent)
        }

        SensorGauge.symbol(settings.tileSensor.symbol,
                           in: NSRect(x: card.midX - side * 0.10, y: card.midY + side * 0.12,
                                      width: side * 0.20, height: side * 0.16),
                           color: palette.secondary)

        SensorGauge.text(reading.text,
                         in: NSRect(x: card.minX + side * 0.16, y: card.midY - side * 0.12,
                                    width: card.width - side * 0.32, height: side * 0.24),
                         weight: .semibold, color: palette.primary, maximumSize: side * 0.26)

        if let caption = reading.caption {
            SensorGauge.text(caption,
                             in: NSRect(x: card.minX + side * 0.12, y: card.minY + side * 0.10,
                                        width: card.width - side * 0.24, height: side * 0.14),
                             weight: .medium, color: palette.secondary, maximumSize: side * 0.11)
        }
    }
}
