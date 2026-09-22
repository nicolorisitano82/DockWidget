import AppKit

/// The next appointments, in a bar.
///
/// A bar rather than a tile because an appointment is a time and a name, and a
/// name does not fit in a square the size of a Dock icon. How many fit is
/// decided by the width: one in a narrow bar, three across the notch.
final class CalendarBarView: BarContentView {
    var onOpen: (() -> Void)?

    private lazy var settings = CalendarSettings.current(resolvedInstance("calendar"))
    private var store: CalendarStore { CalendarStore.shared(resolvedInstance("calendar")) }
    private var token: UUID?
    private var hovered = -1 {
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
        settings = CalendarSettings.current(resolvedInstance("calendar"))
        subscribe()
        store.refresh()
        needsDisplay = true
    }

    /// True when the notch gave this copy two rows to fill.
    private var isTall: Bool { fillsHeight && verticalSlots >= 2 }

    /// Side by side one appointment needs about a hundred and seventy points;
    /// stacked it needs a line, and there is room for three or four of them.
    private var cellCount: Int {
        guard !isTall else {
            return max(2, min(Int(contentPlate.height / 22), 4))
        }
        return max(1, min(Int((contentPlate.width / 170).rounded()), 3))
    }

    private func cells() -> [NSRect] {
        let plate = contentPlate
        let count = CGFloat(cellCount)
        let gap: CGFloat = isTall ? 2 : 10
        // Stacked, an appointment is a line across the whole width, which is
        // what lets the title be read rather than truncated after two words.
        guard !isTall else {
            let height = (plate.height - gap * (count - 1)) / count
            return (0..<cellCount).map { index in
                NSRect(x: plate.minX,
                       y: plate.maxY - CGFloat(index + 1) * height - CGFloat(index) * gap,
                       width: plate.width, height: height)
            }
        }
        let width = (plate.width - gap * (count - 1)) / count
        return (0..<cellCount).map { index in
            NSRect(x: plate.minX + CGFloat(index) * (width + gap), y: plate.minY,
                   width: width, height: plate.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        let palette = TilePalette.resolve(dark: isDarkContext, accent: settings.accent)

        if let problem = store.problem, store.events.isEmpty {
            draw(message: problem, palette: palette)
            return
        }

        let events = store.upcoming(cellCount)
        guard !events.isEmpty else {
            draw(message: T("Niente in programma", "Nothing on"), palette: palette)
            return
        }

        for (index, rect) in cells().enumerated() where index < events.count {
            draw(event: events[index], in: rect, palette: palette, hovered: hovered == index)
        }
    }

    private func draw(message: String, palette: TilePalette) {
        let plate = contentPlate
        let side = min(plate.height * 0.5, 16)
        let box = NSRect(x: plate.minX, y: plate.midY - side / 2, width: side, height: side)
        Gauge.symbol("calendar", in: box, color: palette.secondary)
        let text = NSRect(x: box.maxX + 8, y: plate.minY,
                          width: plate.maxX - box.maxX - 8, height: plate.height)
        draw(message, in: text, size: 12, weight: .medium, colour: palette.secondary)
    }

    private func draw(event: CalendarEvent, in rect: NSRect, palette: TilePalette, hovered: Bool) {
        // The stripe is the calendar's own colour where there is one, so two
        // appointments from two calendars do not look like the same thing.
        let stripe = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.12,
                            width: 3, height: rect.height * 0.76)
        (event.tint ?? palette.accent).withAlphaComponent(event.isRunning ? 1 : 0.8).setFill()
        NSBezierPath(roundedRect: stripe, xRadius: 1.5, yRadius: 1.5).fill()

        if hovered {
            NSColor(calibratedWhite: isDarkContext ? 1 : 0, alpha: 0.07).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -2),
                         xRadius: 6, yRadius: 6).fill()
        }

        let body = NSRect(x: stripe.maxX + 7, y: rect.minY,
                          width: rect.maxX - stripe.maxX - 7, height: rect.height)
        guard body.width > 20 else { return }

        guard !isTall else {
            // One line: when, what, and how long until it.
            let when = event.when()
            let whenWidth = min(measure(when, size: 11.5, weight: .semibold) + 8, 96)
            draw(when, in: NSRect(x: body.minX, y: body.minY, width: whenWidth,
                                  height: body.height),
                 size: 11.5, weight: .semibold, colour: palette.primary)
            let count = event.countdown
            let countWidth = min(measure(count, size: 10.5, weight: .regular) + 6, 72)
            draw(count, in: NSRect(x: body.maxX - countWidth, y: body.minY,
                                   width: countWidth, height: body.height),
                 size: 10.5, weight: .regular,
                 colour: event.isRunning ? palette.accent : palette.secondary)
            let titleBox = NSRect(x: body.minX + whenWidth, y: body.minY,
                                  width: max(body.width - whenWidth - countWidth - 6, 20),
                                  height: body.height)
            draw(event.title, in: titleBox, size: 12, weight: .regular,
                 colour: palette.secondary)
            return
        }

        let upper = NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
        let lower = NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2)

        let when = event.when()
        let count = event.countdown
        let whenWidth = min(measure(when, size: 11.5, weight: .semibold) + 2, upper.width)
        draw(when, in: NSRect(x: upper.minX, y: upper.minY, width: whenWidth, height: upper.height),
             size: 11.5, weight: .semibold, colour: palette.primary)
        let rest = NSRect(x: upper.minX + whenWidth + 6, y: upper.minY,
                          width: max(upper.width - whenWidth - 6, 0), height: upper.height)
        if rest.width > 24 {
            draw(count, in: rest, size: 10.5, weight: .regular,
                 colour: event.isRunning ? palette.accent : palette.secondary)
        }

        let second = settings.showsLocation && !event.location.isEmpty
            ? "\(event.title) · \(event.location)"
            : event.title
        draw(second, in: lower, size: 12, weight: .regular, colour: palette.secondary)
    }

    // MARK: Text

    private var truncating: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func measure(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
    }

    private func draw(_ text: String, in rect: NSRect, size: CGFloat,
                      weight: NSFont.Weight, colour: NSColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: colour, .paragraphStyle: truncating,
        ]
        let height = font.ascender - font.descender
        let box = NSRect(x: rect.minX, y: rect.midY - height / 2,
                         width: rect.width, height: height)
        (text as NSString).draw(in: box, withAttributes: attributes)
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hovered = cells().firstIndex { $0.insetBy(dx: -4, dy: -2).contains(point) } ?? -1
    }

    override func mouseExited(with event: NSEvent) { hovered = -1 }

    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }
}
