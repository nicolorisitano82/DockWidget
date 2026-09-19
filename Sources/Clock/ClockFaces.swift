import AppKit

/// Everything a face needs to draw itself. Sizes are always fractions of the
/// card, which is whatever the Dock's current tile size makes it.
struct ClockFaceContext {
    let card: NSRect
    let date: Date
    let settings: ClockSettings
    let palette: TilePalette
    let timeText: String
    let dateText: String

    var side: CGFloat { card.width }
    var centre: NSPoint { NSPoint(x: card.midX, y: card.midY) }

    var parts: (hours: CGFloat, minutes: CGFloat, seconds: CGFloat) {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let seconds = CGFloat(components.second ?? 0)
        let minutes = CGFloat(components.minute ?? 0) + seconds / 60
        let hours = CGFloat((components.hour ?? 0) % 12) + minutes / 60
        return (hours, minutes, seconds)
    }
}

protocol ClockFace {
    func draw(_ context: ClockFaceContext)
}

// MARK: - Shared drawing

enum ClockDrawing {
    static func hand(from centre: NSPoint, angle: CGFloat, length: CGFloat,
                     width: CGFloat, color: NSColor, tail: CGFloat = 0) {
        let direction = NSPoint(x: sin(angle), y: cos(angle))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre.x - direction.x * tail, y: centre.y - direction.y * tail))
        path.line(to: NSPoint(x: centre.x + direction.x * length, y: centre.y + direction.y * length))
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    static func fittedFont(for text: NSString, maxWidth: CGFloat,
                           startingAt size: CGFloat, weight: NSFont.Weight) -> NSFont {
        var font = NSFont.roundedSystemFont(ofSize: size, weight: weight)
        var width = text.size(withAttributes: [.font: font]).width
        var attempts = 0
        while width > maxWidth, font.pointSize > 4, attempts < 24 {
            font = NSFont.roundedSystemFont(ofSize: font.pointSize * min(0.94, maxWidth / width), weight: weight)
            width = text.size(withAttributes: [.font: font]).width
            attempts += 1
        }
        return font
    }

    /// An arc drawn clockwise from twelve o'clock, the way a clock reads.
    static func arc(centre: NSPoint, radius: CGFloat, fraction: CGFloat,
                    width: CGFloat, color: NSColor) {
        guard fraction > 0 else { return }
        let path = NSBezierPath()
        path.appendArc(withCenter: centre, radius: radius,
                       startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

// MARK: - Faces

/// Ticks and hands: the face everyone already knows how to read.
struct AnalogFace: ClockFace {
    func draw(_ context: ClockFaceContext) {
        let palette = context.palette
        let side = context.side
        let centre = context.centre
        let radius = side * 0.40

        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6
            let isQuarter = index % 3 == 0
            let length = side * (isQuarter ? 0.075 : 0.045)
            let outer = NSPoint(x: centre.x + sin(angle) * radius, y: centre.y + cos(angle) * radius)
            let inner = NSPoint(x: centre.x + sin(angle) * (radius - length),
                                y: centre.y + cos(angle) * (radius - length))
            let tick = NSBezierPath()
            tick.move(to: inner)
            tick.line(to: outer)
            tick.lineWidth = side * (isQuarter ? 0.028 : 0.018)
            tick.lineCapStyle = .round
            (isQuarter ? palette.primary.withAlphaComponent(0.85) : palette.faint).setStroke()
            tick.stroke()
        }

        if context.settings.showsDate {
            let text = context.dateText.uppercased() as NSString
            let box = NSRect(x: context.card.minX, y: centre.y - side * 0.28,
                             width: context.card.width, height: side * 0.16)
            text.drawCentered(in: box, attributes: [
                .font: NSFont.roundedSystemFont(ofSize: side * 0.115, weight: .semibold),
                .foregroundColor: palette.secondary,
                .kern: side * 0.004,
            ])
        }

        let parts = context.parts
        ClockDrawing.hand(from: centre, angle: parts.hours * .pi / 6, length: radius * 0.55,
                          width: side * 0.072, color: palette.primary)
        ClockDrawing.hand(from: centre, angle: parts.minutes * .pi / 30, length: radius * 0.86,
                          width: side * 0.050, color: palette.primary)
        if context.settings.showsSeconds {
            ClockDrawing.hand(from: centre, angle: parts.seconds * .pi / 30, length: radius * 0.92,
                              width: side * 0.020, color: palette.accent, tail: radius * 0.22)
        }

        let hub = side * (context.settings.showsSeconds ? 0.030 : 0.036)
        palette.primary.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - hub, y: centre.y - hub,
                                    width: hub * 2, height: hub * 2)).fill()
        if context.settings.showsSeconds {
            let inner = side * 0.014
            palette.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: centre.x - inner, y: centre.y - inner,
                                        width: inner * 2, height: inner * 2)).fill()
        }
    }
}

/// The time as numerals, which is the only face that stays readable when the
/// Dock is set to its smallest tiles.
struct DigitalFace: ClockFace {
    func draw(_ context: ClockFaceContext) {
        let palette = context.palette
        let side = context.side
        let card = context.card
        let time = context.timeText as NSString
        let maxWidth = card.width * 0.84

        let timeFont = ClockDrawing.fittedFont(
            for: time, maxWidth: maxWidth,
            startingAt: side * (context.settings.showsSeconds ? 0.245 : 0.30), weight: .semibold
        )
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: timeFont, .foregroundColor: palette.primary,
        ]

        guard context.settings.showsDate else {
            time.drawCentered(in: card, attributes: timeAttributes)
            return
        }
        let date = context.dateText.uppercased() as NSString
        let dateFont = ClockDrawing.fittedFont(for: date, maxWidth: maxWidth,
                                               startingAt: side * 0.135, weight: .bold)
        time.drawCentered(in: NSRect(x: card.minX, y: card.midY + side * 0.03,
                                     width: card.width, height: side * 0.34),
                          attributes: timeAttributes)
        date.drawCentered(in: NSRect(x: card.minX, y: card.midY - side * 0.24,
                                     width: card.width, height: side * 0.20),
                          attributes: [
                              .font: dateFont,
                              .foregroundColor: palette.accent,
                              .kern: side * 0.006,
                          ])
    }
}

/// Two split-flap cards, hours over minutes, with the seam across each one.
struct FlipFace: ClockFace {
    func draw(_ context: ClockFaceContext) {
        let palette = context.palette
        let card = context.card
        let side = context.side
        let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)

        let hour24 = components.hour ?? 0
        let showsAmPm = context.settings.hourFormat == .h12
            || (context.settings.hourFormat == .system && context.timeText.count > 5
                && !context.timeText.hasPrefix(String(format: "%02d", hour24)))
        let hour = showsAmPm ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24

        let gap = side * 0.05
        let height = (card.height - gap) / 2
        let top = NSRect(x: card.minX, y: card.midY + gap / 2, width: card.width, height: height)
        let bottom = NSRect(x: card.minX, y: card.minY, width: card.width, height: height)

        flap(String(format: "%02d", hour), in: top, context: context, color: palette.primary)
        flap(String(format: "%02d", components.minute ?? 0), in: bottom, context: context,
             color: context.settings.showsSeconds ? palette.accent : palette.primary)
    }

    private func flap(_ text: String, in rect: NSRect, context: ClockFaceContext, color: NSColor) {
        let palette = context.palette
        let radius = rect.height * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0, alpha: 0.10).setFill()
        path.fill()

        let string = text as NSString
        let font = ClockDrawing.fittedFont(for: string, maxWidth: rect.width * 0.72,
                                           startingAt: rect.height * 0.86, weight: .bold)
        string.drawCentered(in: rect, attributes: [.font: font, .foregroundColor: color])

        // The seam a split-flap card folds along.
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: rect.minX + rect.width * 0.06, y: rect.midY))
        seam.line(to: NSPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY))
        seam.lineWidth = max(1, rect.height * 0.018)
        palette.card.setStroke()
        seam.stroke()
    }
}

/// Concentric arcs. No numerals to squint at: the shape carries the time.
struct RingsFace: ClockFace {
    func draw(_ context: ClockFaceContext) {
        let palette = context.palette
        let side = context.side
        let centre = context.centre
        let parts = context.parts
        let width = side * 0.058
        // Explicit, because withAlphaComponent replaces an alpha rather than
        // scaling it: asking a colour that is already faint for 0.35 makes it
        // three times more solid, and the tracks swallow the rings.
        let track = NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0, alpha: 0.11)

        let rings: [(radius: CGFloat, fraction: CGFloat, color: NSColor)] = [
            (side * 0.40, parts.hours / 12, palette.accent),
            (side * 0.40 - width * 1.6, parts.minutes / 60, palette.primary),
            (side * 0.40 - width * 3.2, parts.seconds / 60,
             context.settings.showsSeconds ? palette.secondary : .clear),
        ]

        for ring in rings where ring.color != .clear {
            ClockDrawing.arc(centre: centre, radius: ring.radius, fraction: 1,
                             width: width, color: track)
            ClockDrawing.arc(centre: centre, radius: ring.radius, fraction: ring.fraction,
                             width: width, color: ring.color)
        }

        let text = (context.settings.showsDate ? context.dateText.uppercased() : context.timeText) as NSString
        let inner = side * 0.40 - width * 4.4
        let font = ClockDrawing.fittedFont(for: text, maxWidth: inner * 1.9,
                                           startingAt: side * 0.14, weight: .bold)
        text.drawCentered(in: NSRect(x: centre.x - inner, y: centre.y - inner,
                                     width: inner * 2, height: inner * 2),
                          attributes: [.font: font, .foregroundColor: palette.secondary])
    }
}

/// Bauhaus: a hairline circle, one mark at twelve, nothing else.
struct MinimalFace: ClockFace {
    func draw(_ context: ClockFaceContext) {
        let palette = context.palette
        let side = context.side
        let centre = context.centre
        let radius = side * 0.40

        let circle = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius,
                                                 width: radius * 2, height: radius * 2))
        circle.lineWidth = max(1, side * 0.012)
        palette.faint.setStroke()
        circle.stroke()

        let dot = side * 0.032
        palette.accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - dot, y: centre.y + radius - dot,
                                    width: dot * 2, height: dot * 2)).fill()

        let parts = context.parts
        ClockDrawing.hand(from: centre, angle: parts.hours * .pi / 6, length: radius * 0.50,
                          width: side * 0.030, color: palette.primary)
        ClockDrawing.hand(from: centre, angle: parts.minutes * .pi / 30, length: radius * 0.80,
                          width: side * 0.024, color: palette.primary)
        if context.settings.showsSeconds {
            ClockDrawing.hand(from: centre, angle: parts.seconds * .pi / 30, length: radius * 0.80,
                              width: side * 0.012, color: palette.accent)
        }

        if context.settings.showsDate {
            let text = context.dateText.uppercased() as NSString
            text.drawCentered(in: NSRect(x: context.card.minX, y: centre.y - side * 0.30,
                                         width: context.card.width, height: side * 0.14),
                              attributes: [
                                  .font: NSFont.roundedSystemFont(ofSize: side * 0.10, weight: .medium),
                                  .foregroundColor: palette.secondary,
                                  .kern: side * 0.006,
                              ])
        }
    }
}
