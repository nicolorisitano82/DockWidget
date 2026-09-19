import AppKit

/// Colours for one tile, resolved for the current theme.
struct TilePalette {
    var card: NSColor
    var cardEdge: NSColor
    var primary: NSColor
    var secondary: NSColor
    var faint: NSColor
    var accent: NSColor

    static func resolve(dark: Bool, accent: NSColor) -> TilePalette {
        if dark {
            return TilePalette(
                card: NSColor(calibratedWhite: 0.13, alpha: 1.0),
                cardEdge: NSColor(calibratedWhite: 1.0, alpha: 0.14),
                primary: NSColor(calibratedWhite: 0.97, alpha: 1.0),
                secondary: NSColor(calibratedWhite: 0.70, alpha: 1.0),
                faint: NSColor(calibratedWhite: 1.0, alpha: 0.22),
                accent: accent
            )
        }
        return TilePalette(
            card: NSColor(calibratedWhite: 0.98, alpha: 1.0),
            cardEdge: NSColor(calibratedWhite: 0.0, alpha: 0.10),
            primary: NSColor(calibratedWhite: 0.11, alpha: 1.0),
            secondary: NSColor(calibratedWhite: 0.42, alpha: 1.0),
            faint: NSColor(calibratedWhite: 0.0, alpha: 0.16),
            accent: accent
        )
    }
}

enum TileGeometry {
    /// Dock icon artwork does not fill its slot; it sits in a squircle inset from the edges.
    /// Matching that inset is what makes a widget sit level with the icons beside it.
    static let artworkInset: CGFloat = 0.075
    static let cornerRatio: CGFloat = 0.2237

    static func artworkRect(in bounds: NSRect) -> NSRect {
        let side = min(bounds.width, bounds.height)
        let inset = side * artworkInset
        let square = NSRect(
            x: bounds.midX - side / 2 + inset,
            y: bounds.midY - side / 2 + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )
        return square
    }

    static func cardPath(in rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) * cornerRatio
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

extension NSFont {
    /// Rounded system font, falling back to the plain one where the design is unavailable.
    static func roundedSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else { return base }
        return rounded
    }
}

extension NSString {
    func drawCentered(in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let size = self.size(withAttributes: attributes)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        draw(at: origin, withAttributes: attributes)
    }
}
