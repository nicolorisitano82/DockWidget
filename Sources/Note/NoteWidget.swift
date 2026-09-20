import AppKit

struct NoteSettings: Equatable {
    var text: String = ""
    var accentHex = "#FFD60A"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemYellow }

    enum Key {
        static func text(_ instance: String) -> String { "\(instance).text" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: NoteSettings { current("note") }

    static func current(_ instance: String) -> NoteSettings {
        let store = SettingsStore.shared
        let defaults = NoteSettings()
        return NoteSettings(
            text: store.string(Key.text(instance), or: defaults.text),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "note") {
        SettingsStore.shared.set([Key.text(instance): text, Key.accent(instance): accentHex])
    }
}

/// A note, kept where you can read it without opening anything.
///
/// Two or more Dock tiles wide: at one tile there is room for a word, which is
/// not a note.
final class NoteBarView: BarContentView {
    var onEdit: (() -> Void)?

    private lazy var settings = NoteSettings.current(resolvedInstance("note"))
    private var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    private var pressed = false {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }

    override func reloadSettings() {
        settings = NoteSettings.current(resolvedInstance("note"))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = self.plate
        let dark = isDarkContext
        let palette = TilePalette.resolve(dark: dark, accent: settings.accent)

        drawWidgetBackground()
        let radius = plate.height * TileGeometry.cornerRatio
        let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
        // The note lights up under the pointer, over whatever panel is there.
        if pressed || hovered {
            NSColor(calibratedWhite: dark ? 1 : 0, alpha: pressed ? 0.12 : 0.07).setFill()
            path.fill()
        }

        // A strip of the accent down the left edge, the way a paper tab reads.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        palette.accent.setFill()
        NSRect(x: plate.minX, y: plate.minY, width: plate.height * 0.09, height: plate.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let inset = plate.height * 0.16
        let box = NSRect(x: plate.minX + plate.height * 0.22, y: plate.minY + inset * 0.5,
                         width: plate.width - plate.height * 0.34, height: plate.height - inset)

        let isEmpty = settings.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let text = isEmpty ? T("Scrivi qui", "Write here") : settings.text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = -plate.height * 0.04

        (text as NSString).draw(in: box, withAttributes: [
            .font: NSFont.systemFont(ofSize: plate.height * 0.26, weight: .medium),
            .foregroundColor: isEmpty ? palette.secondary : palette.primary,
            .paragraphStyle: paragraph,
        ])
    }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onEdit?()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
}
