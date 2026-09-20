import AppKit

/// A row of square cells, each one an icon with an action behind it.
///
/// A row rather than a grid: across two Dock tiles the icon band is about
/// 68 by 30 points, so a 2×2 grid would mean cells twice as wide as they are
/// tall. Four in a row are square.
final class ActionsBarView: BarContentView {
    var onRun: ((ActionKind) -> Void)?

    private lazy var settings = ActionsSettings.current(resolvedInstance("actions"))
    private var hovered: Int? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    private var pressed: Int? {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }

    override func reloadSettings() {
        settings = ActionsSettings.current(resolvedInstance("actions"))
        needsDisplay = true
    }

    private func cells() -> [NSRect] {
        let plate = self.plate
        let count = CGFloat(ActionsSettings.slotCount)
        let gap = controlGap
        // Never taller than the icon band, never wider than its share of it.
        let side = min(plate.height, (plate.width - gap * (count - 1)) / count)
        let total = side * count + gap * (count - 1)
        var x = plate.midX - total / 2
        return (0..<ActionsSettings.slotCount).map { _ in
            defer { x += side + gap }
            return NSRect(x: x, y: plate.midY - side / 2, width: side, height: side)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        for (index, rect) in cells().enumerated() {
            draw(slot: settings.slots[index], in: rect, index: index)
        }
    }

    private func draw(slot: ActionSlot, in rect: NSRect, index: Int) {
        let radius = rect.width * 0.28
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let isPressed = pressed == index
        let isHovered = hovered == index

        if slot.isEmpty {
            NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0,
                    alpha: isHovered ? 0.16 : 0.08).setFill()
            path.fill()
        } else {
            var background = slot.background
            if isPressed {
                background = background.blended(withFraction: 0.25, of: .black) ?? background
            } else if isHovered {
                background = background.blended(withFraction: 0.18, of: .white) ?? background
            }
            background.setFill()
            path.fill()
        }

        var glyph = rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.24)
        if isPressed {
            glyph = glyph.insetBy(dx: glyph.width * 0.07, dy: glyph.height * 0.07)
        }
        let color = slot.isEmpty ? NSColor(calibratedWhite: 0.6, alpha: 0.9) : slot.icon
        let configuration = NSImage.SymbolConfiguration(pointSize: glyph.height, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: slot.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let scale = min(glyph.width / size.width, glyph.height / size.height)
        let box = NSRect(x: glyph.midX - size.width * scale / 2, y: glyph.midY - size.height * scale / 2,
                         width: size.width * scale, height: size.height * scale)
        image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }

    // MARK: Interaction

    private func index(at point: NSPoint) -> Int? {
        cells().firstIndex { $0.insetBy(dx: -2, dy: -2).contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressed != nil else { return }
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let target = index(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil }
        guard let pressed, target == pressed else { return }
        onRun?(settings.slots[pressed].kind)
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        let menu = NSMenu()
        let title = NSMenuItem(title: settings.slots[index].kind.summary, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let configure = NSMenuItem(title: T("Configura…", "Configure…"), action: #selector(configure), keyEquivalent: "")
        configure.target = self
        menu.addItem(configure)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func configure() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.nicolo.dockwidgets.selectWidget"),
            object: "actions", userInfo: nil, deliverImmediately: true
        )
    }
}
