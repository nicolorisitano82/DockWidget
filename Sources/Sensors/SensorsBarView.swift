import AppKit

/// Several sensors side by side, one Dock tile each.
final class SensorsBarView: BarContentView {
    private lazy var settings = SensorsSettings.current(resolvedInstance("sensors"))
    private var token: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        subscribe()
    }

    deinit {
        if let token { SensorSampler.shared.removeListener(token) }
    }

    override func reloadSettings() {
        settings = SensorsSettings.current(resolvedInstance("sensors"))
        subscribe()
        needsDisplay = true
    }

    override var tileCount: Int {
        didSet { if tileCount != oldValue { subscribe() } }
    }

    private var visible: [SensorID] {
        settings.visibleBarSensors(count: max(tileCount, 1))
    }

    private func subscribe() {
        if let token { SensorSampler.shared.removeListener(token) }
        SensorSampler.shared.setInterval(settings.refresh)
        token = SensorSampler.shared.addListener(for: Set(visible)) { [weak self] in
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        let plate = contentPlate
        let sensors = visible
        let cellWidth = plate.width / CGFloat(max(sensors.count, 1))

        for (index, sensor) in sensors.enumerated() {
            let cell = NSRect(x: plate.minX + CGFloat(index) * cellWidth, y: plate.minY,
                              width: cellWidth, height: plate.height)
            draw(sensor: sensor, in: cell.insetBy(dx: cellWidth * 0.06, dy: plate.height * 0.04))
        }
    }

    private func draw(sensor: SensorID, in rect: NSRect) {
        let palette = TilePalette.resolve(dark: isDarkContext,
                                          accent: settings.accent)
        let reading = SensorSampler.shared.reading(sensor)
        let side = min(rect.width, rect.height)
        let box = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        guard let fraction = reading.fraction else {
            // No full scale — network throughput — so the shape carries it.
            Gauge.text(reading.text,
                             in: NSRect(x: rect.minX, y: rect.midY - rect.height * 0.05,
                                        width: rect.width, height: rect.height * 0.46),
                             weight: .semibold, color: palette.primary,
                             maximumSize: rect.height * 0.30)
            if settings.showsSparkline {
                Gauge.sparkline(in: NSRect(x: rect.minX + rect.width * 0.08,
                                                 y: rect.minY + rect.height * 0.06,
                                                 width: rect.width * 0.84, height: rect.height * 0.30),
                                      samples: SensorSampler.shared.trend(sensor),
                                      color: palette.accent)
            }
            return
        }

        // The same arrangement as the square tile, only smaller: the number
        // lives inside the ring, because a Dock cell has no room beside it.
        Gauge.ring(in: box, fraction: fraction, width: side * 0.11,
                         color: palette.accent, track: Gauge.trackColor())
        Gauge.symbol(sensor.symbol,
                           in: NSRect(x: box.midX - side * 0.11, y: box.midY + side * 0.10,
                                      width: side * 0.22, height: side * 0.15),
                           color: palette.secondary)
        Gauge.text(reading.text,
                         in: NSRect(x: box.minX + side * 0.16, y: box.midY - side * 0.20,
                                    width: box.width - side * 0.32, height: side * 0.28),
                         weight: .semibold, color: palette.primary, maximumSize: side * 0.30)
    }
}
