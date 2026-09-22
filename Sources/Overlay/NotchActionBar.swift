import AppKit

/// A thin line of actions under the last widget in the notch.
///
/// Small on purpose: these are things you reach for, not things you read. Up to
/// ten of them, laid out from the middle outwards so the line stays centred
/// under the panel however many there are.
final class NotchActionBar: NSView {
    var onRun: ((ActionKind) -> Void)?

    static let height: CGFloat = 22

    private var slots: [ActionSlot] = []
    private var hovered = -1 {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    private var pressed = -1 {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reload() {
        // The cells are an actions widget like any other, so they are edited
        // with the same pane and stored the same way.
        slots = ActionsSettings.current(NotchSettings.actionBarInstance).slots
            .filter { !$0.isEmpty }
        needsDisplay = true
    }

    var isEmpty: Bool { slots.isEmpty }
    var count: Int { slots.count }

    private let side: CGFloat = 14
    private let gap: CGFloat = 13

    private func cells() -> [NSRect] {
        guard !slots.isEmpty else { return [] }
        let total = CGFloat(slots.count) * side + CGFloat(slots.count - 1) * gap
        var x = bounds.midX - total / 2
        return slots.map { _ in
            defer { x += side + gap }
            return NSRect(x: x, y: bounds.midY - side / 2, width: side, height: side)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, rect) in cells().enumerated() {
            let slot = slots[index]
            if hovered == index || pressed == index {
                NSColor(calibratedWhite: 1, alpha: pressed == index ? 0.26 : 0.16).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: -4),
                             xRadius: 7, yRadius: 7).fill()
            }
            // White on the panel's own black: down here they are marks to aim
            // at, not cells to look at, and the colours of the widget would
            // make the line shout.
            Gauge.symbol(slot.symbol, in: rect, color: .white)
        }
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
        hovered = cells().firstIndex { $0.insetBy(dx: -5, dy: -4).contains(point) } ?? -1
    }

    override func mouseExited(with event: NSEvent) { hovered = -1 }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = cells().firstIndex { $0.insetBy(dx: -5, dy: -4).contains(point) } ?? -1
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = -1 }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = cells().firstIndex(where: { $0.insetBy(dx: -5, dy: -4).contains(point) }),
              index == pressed else { return }
        onRun?(slots[index].kind)
    }
}
