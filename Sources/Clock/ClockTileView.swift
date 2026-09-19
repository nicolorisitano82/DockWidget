import AppKit

final class ClockTileView: TileView {
    private var settings = ClockSettings.current
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private var localeObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rebuildFormatters()
        for name in [NSLocale.currentLocaleDidChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuildFormatters()
                self?.needsDisplay = true
            }
            localeObservers.append(token)
        }
    }

    deinit {
        localeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Pinned instant used when rendering app icons, where "now" would be wrong.
    var fixedDate: Date?

    private var renderDate: Date { fixedDate ?? Date() }

    override func reloadSettings() {
        settings = ClockSettings.current
        accent = settings.accent
        rebuildFormatters()
        needsDisplay = true
    }

    private func rebuildFormatters() {
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.timeZone = .autoupdatingCurrent
        timeFormatter.dateFormat = settings.timeFormat()

        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("EEE d")
    }

    /// What the tile currently shows, so the plug-in can skip redraws that would
    /// paint the same pixels.
    func renderToken(at date: Date = Date()) -> Int {
        let unit: TimeInterval = settings.showsSeconds || settings.style == .analog ? 1 : 60
        return Int(date.timeIntervalSince1970 / unit)
    }

    var formattedTime: String { timeFormatter.string(from: Date()) }

    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        switch settings.style {
        case .analog: drawAnalogFace(in: card)
        case .digital: drawDigitalFace(in: card)
        }
    }

    // MARK: Analog

    private func drawAnalogFace(in card: NSRect) {
        let palette = self.palette
        let side = card.width
        let center = NSPoint(x: card.midX, y: card.midY)
        let radius = side * 0.40

        // Hour ticks. The four quarters are longer so the face reads at 32 pt.
        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6
            let isQuarter = index % 3 == 0
            let length = side * (isQuarter ? 0.075 : 0.045)
            let width = side * (isQuarter ? 0.028 : 0.018)
            let outer = NSPoint(x: center.x + sin(angle) * radius, y: center.y + cos(angle) * radius)
            let inner = NSPoint(x: center.x + sin(angle) * (radius - length), y: center.y + cos(angle) * (radius - length))
            let tick = NSBezierPath()
            tick.move(to: inner)
            tick.line(to: outer)
            tick.lineWidth = width
            tick.lineCapStyle = .round
            (isQuarter ? palette.primary.withAlphaComponent(0.85) : palette.faint).setStroke()
            tick.stroke()
        }

        let now = renderDate
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let seconds = CGFloat(parts.second ?? 0)
        let minutes = CGFloat(parts.minute ?? 0) + seconds / 60
        let hours = CGFloat((parts.hour ?? 0) % 12) + minutes / 60

        if settings.showsDate {
            let text = dateFormatter.string(from: now).uppercased() as NSString
            let font = NSFont.roundedSystemFont(ofSize: side * 0.115, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: palette.secondary,
                .kern: side * 0.004,
            ]
            let box = NSRect(x: card.minX, y: center.y - side * 0.28, width: card.width, height: side * 0.16)
            text.drawCentered(in: box, attributes: attributes)
        }

        drawHand(from: center, angle: hours * .pi / 6, length: radius * 0.55,
                 width: side * 0.072, color: palette.primary)
        drawHand(from: center, angle: minutes * .pi / 30, length: radius * 0.86,
                 width: side * 0.050, color: palette.primary)

        if settings.showsSeconds {
            drawHand(from: center, angle: seconds * .pi / 30, length: radius * 0.92,
                     width: side * 0.020, color: palette.accent, tailLength: radius * 0.22)
        }

        let hubRadius = side * (settings.showsSeconds ? 0.030 : 0.036)
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - hubRadius, y: center.y - hubRadius,
                                              width: hubRadius * 2, height: hubRadius * 2))
        palette.primary.setFill()
        hub.fill()
        if settings.showsSeconds {
            let inner = side * 0.014
            palette.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner,
                                        width: inner * 2, height: inner * 2)).fill()
        }
    }

    private func drawHand(from center: NSPoint, angle: CGFloat, length: CGFloat,
                          width: CGFloat, color: NSColor, tailLength: CGFloat = 0) {
        let direction = NSPoint(x: sin(angle), y: cos(angle))
        let tip = NSPoint(x: center.x + direction.x * length, y: center.y + direction.y * length)
        let tail = NSPoint(x: center.x - direction.x * tailLength, y: center.y - direction.y * tailLength)
        let hand = NSBezierPath()
        hand.move(to: tail)
        hand.line(to: tip)
        hand.lineWidth = width
        hand.lineCapStyle = .round
        color.setStroke()
        hand.stroke()
    }

    // MARK: Digital

    private func drawDigitalFace(in card: NSRect) {
        let palette = self.palette
        let side = card.width
        let now = renderDate
        let time = timeFormatter.string(from: now) as NSString
        let maxWidth = card.width * 0.84

        let timeFont = fittedFont(for: time, maxWidth: maxWidth,
                                  startingAt: side * (settings.showsSeconds ? 0.245 : 0.30),
                                  weight: .semibold)
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: timeFont,
            .foregroundColor: palette.primary,
        ]

        if settings.showsDate {
            let date = dateFormatter.string(from: now).uppercased() as NSString
            let dateFont = fittedFont(for: date, maxWidth: maxWidth, startingAt: side * 0.135, weight: .bold)
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: palette.accent,
                .kern: side * 0.006,
            ]
            time.drawCentered(in: NSRect(x: card.minX, y: card.midY + side * 0.03,
                                         width: card.width, height: side * 0.34), attributes: timeAttributes)
            date.drawCentered(in: NSRect(x: card.minX, y: card.midY - side * 0.24,
                                         width: card.width, height: side * 0.20), attributes: dateAttributes)
        } else {
            time.drawCentered(in: card, attributes: timeAttributes)
        }
    }

    private func fittedFont(for text: NSString, maxWidth: CGFloat,
                            startingAt size: CGFloat, weight: NSFont.Weight) -> NSFont {
        var font = NSFont.roundedSystemFont(ofSize: size, weight: weight)
        var width = text.size(withAttributes: [.font: font]).width
        var guard_ = 0
        while width > maxWidth, font.pointSize > 4, guard_ < 24 {
            let next = font.pointSize * min(0.94, maxWidth / width)
            font = NSFont.roundedSystemFont(ofSize: next, weight: weight)
            width = text.size(withAttributes: [.font: font]).width
            guard_ += 1
        }
        return font
    }
}
