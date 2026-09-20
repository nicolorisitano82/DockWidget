import AppKit

/// The panel drawn behind a bar widget.
///
/// A square tile sits on an opaque card, which is why it reads on any
/// wallpaper. A bar has nothing underneath but the Dock's glass — and in
/// Liquid Glass that glass is transparent enough that the wallpaper, not the
/// theme, decides whether the text is legible. This puts the same card back.
enum WidgetChrome {
    static let key = "widgets.background"

    static var showsBackground: Bool {
        SettingsStore.shared.bool(key, or: true)
    }

    static func setShowsBackground(_ value: Bool) {
        SettingsStore.shared.set(value, for: key)
    }
}

extension BarContentView {
    /// Draws the widget's panel and returns the area to draw inside.
    @discardableResult
    func drawWidgetBackground() -> NSRect {
        let plate = self.plate
        guard WidgetChrome.showsBackground else { return plate }

        let palette = TilePalette.resolve(dark: isDarkContext, accent: .systemBlue)
        let radius = plate.height * TileGeometry.cornerRatio
        let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: isDarkContext ? 0.5 : 0.22)
        shadow.shadowBlurRadius = plate.height * 0.16
        shadow.shadowOffset = NSSize(width: 0, height: -plate.height * 0.04)
        shadow.set()
        palette.card.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        palette.cardEdge.setStroke()
        path.lineWidth = max(1, plate.height * 0.02)
        path.stroke()
        return plate
    }
}
