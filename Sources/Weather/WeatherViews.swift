import AppKit

/// The weather where you told it to look.
final class WeatherBarView: BarContentView {
    var onOpen: (() -> Void)?

    private lazy var settings = WeatherSettings.current(resolvedInstance("weather"))
    private var store: WeatherStore { WeatherStore.shared(resolvedInstance("weather")) }
    private var token: UUID?
    private var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        DispatchQueue.main.async { [weak self] in self?.subscribe() }
    }

    deinit {
        if let token { store.removeListener(token) }
    }

    private func subscribe() {
        guard token == nil else { return }
        token = store.addListener { [weak self] in self?.needsDisplay = true }
    }

    override func reloadSettings() {
        settings = WeatherSettings.current(resolvedInstance("weather"))
        subscribe()
        store.refresh()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        let palette = TilePalette.resolve(dark: isDarkContext, accent: settings.accent)
        let plate = contentPlate

        guard let reading = store.reading else {
            let message = store.problem ?? T("In ascolto…", "Listening…")
            let side = min(plate.height * 0.5, 16)
            let box = NSRect(x: plate.minX, y: plate.midY - side / 2, width: side, height: side)
            Gauge.symbol("cloud.fill", in: box, color: palette.secondary)
            draw(message, in: NSRect(x: box.maxX + 8, y: plate.minY,
                                     width: plate.maxX - box.maxX - 8, height: plate.height),
                 size: 12, weight: .medium, colour: palette.secondary)
            return
        }

        if hovered {
            NSColor(calibratedWhite: isDarkContext ? 1 : 0, alpha: 0.06).setFill()
            NSBezierPath(roundedRect: plate.insetBy(dx: -4, dy: -2),
                         xRadius: 6, yRadius: 6).fill()
        }

        // What is happening now, on the left; what happens next, filling
        // whatever width is left. A bar as wide as the notch has room for both,
        // and leaving it empty was the whole complaint.
        let headWidth = min(head(reading, in: plate), plate.width)
        draw(now: reading, in: NSRect(x: plate.minX, y: plate.minY,
                                      width: headWidth, height: plate.height),
             palette: palette)

        let rest = NSRect(x: plate.minX + headWidth + 12, y: plate.minY,
                          width: max(plate.maxX - plate.minX - headWidth - 12, 0),
                          height: plate.height)
        guard rest.width >= 90, !reading.hours.isEmpty else { return }
        draw(hours: reading.hours, in: rest, palette: palette)
    }

    /// How much room the current conditions need: the symbol, the degrees, and
    /// the two lines beside them.
    private func head(_ reading: WeatherReading, in plate: NSRect) -> CGFloat {
        let symbolSide = min(plate.height * 0.66, 24)
        let degreesSize = min(plate.height * 0.62, 21)
        let degrees = "\(Int(reading.temperature.rounded()))°"
        let lines = max(measure(settings.place, size: 10.5, weight: .semibold),
                        measure(summaryLine(reading), size: 10, weight: .regular))
        return symbolSide + 8 + measure(degrees, size: degreesSize, weight: .semibold)
            + 10 + min(lines, 150)
    }

    private func summaryLine(_ reading: WeatherReading) -> String {
        guard settings.showsRange else { return reading.summary }
        return "\(reading.summary)  ↑\(Int(reading.high.rounded()))°  ↓\(Int(reading.low.rounded()))°"
    }

    private func draw(now reading: WeatherReading, in rect: NSRect, palette: TilePalette) {
        let symbolSide = min(rect.height * 0.66, 24)
        let symbol = NSRect(x: rect.minX, y: rect.midY - symbolSide / 2,
                            width: symbolSide, height: symbolSide)
        Gauge.symbol(reading.symbol, in: symbol, color: palette.accent)

        let degreesSize = min(rect.height * 0.62, 21)
        let degrees = "\(Int(reading.temperature.rounded()))°"
        let degreesWidth = measure(degrees, size: degreesSize, weight: .semibold) + 2
        draw(degrees, in: NSRect(x: symbol.maxX + 8, y: rect.minY,
                                 width: degreesWidth, height: rect.height),
             size: degreesSize, weight: .semibold, colour: palette.primary)

        let column = NSRect(x: symbol.maxX + 8 + degreesWidth + 10, y: rect.minY,
                            width: max(rect.maxX - symbol.maxX - degreesWidth - 18, 0),
                            height: rect.height)
        guard column.width > 30 else { return }
        draw(settings.place,
             in: NSRect(x: column.minX, y: column.midY,
                        width: column.width, height: column.height / 2),
             size: 10.5, weight: .semibold, colour: palette.primary)
        draw(summaryLine(reading),
             in: NSRect(x: column.minX, y: column.minY,
                        width: column.width, height: column.height / 2),
             size: 10, weight: .regular, colour: palette.secondary)
    }

    /// The next hours: the hour, its sky, its temperature.
    private func draw(hours: [WeatherHour], in rect: NSRect, palette: TilePalette) {
        let cellWidth: CGFloat = 40
        let count = min(hours.count, max(Int(rect.width / cellWidth), 1))
        guard count >= 2 else { return }
        let width = rect.width / CGFloat(count)

        for index in 0..<count {
            let hour = hours[index]
            let cell = NSRect(x: rect.minX + CGFloat(index) * width, y: rect.minY,
                              width: width, height: rect.height)
            let third = cell.height / 3

            centred(hour.label,
                    in: NSRect(x: cell.minX, y: cell.maxY - third,
                               width: cell.width, height: third),
                    size: min(third * 0.82, 9.5), weight: .semibold,
                    colour: palette.secondary)

            let side = min(third * 0.96, 14)
            Gauge.symbol(hour.symbol,
                         in: NSRect(x: cell.midX - side / 2, y: cell.minY + third + (third - side) / 2,
                                    width: side, height: side),
                         color: palette.primary)

            centred("\(Int(hour.temperature.rounded()))°",
                    in: NSRect(x: cell.minX, y: cell.minY, width: cell.width, height: third),
                    size: min(third * 0.88, 10.5), weight: .medium, colour: palette.primary)
        }
    }

    private func centred(_ text: String, in rect: NSRect, size: CGFloat,
                         weight: NSFont.Weight, colour: NSColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let height = font.ascender - font.descender
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2,
                                           width: rect.width, height: height),
                                withAttributes: [.font: font, .foregroundColor: colour,
                                                 .paragraphStyle: paragraph])
    }

    // MARK: Text

    private var truncating: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func measure(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
        ]).width
    }

    private func draw(_ text: String, in rect: NSRect, size: CGFloat,
                      weight: NSFont.Weight, colour: NSColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let height = font.ascender - font.descender
        let box = NSRect(x: rect.minX, y: rect.midY - height / 2,
                         width: rect.width, height: height)
        (text as NSString).draw(in: box, withAttributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: truncating,
        ])
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { onOpen?() }
}
