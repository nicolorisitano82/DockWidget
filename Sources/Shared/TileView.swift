import AppKit

/// Base view for everything drawn into a Dock tile.
///
/// The Dock hands the content view a square slot whose side follows the user's
/// `tilesize`, so nothing here may assume pixels: every measurement is a
/// fraction of `bounds`.
class TileView: NSView {
    var accent: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }

    var palette: TilePalette {
        TilePalette.resolve(dark: SystemAppearance.shared.isDark, accent: accent)
    }

    private var appearanceObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = SystemAppearance.shared.nsAppearance
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .tileAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.appearance = SystemAppearance.shared.nsAppearance
            self.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TileView is only ever built in code") }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    /// Re-read anything the user can change in the host app.
    func reloadSettings() {}

    /// Draws the rounded card every widget sits on, and returns its rect.
    @discardableResult
    func drawCard(shadow: Bool = true) -> NSRect {
        let rect = TileGeometry.artworkRect(in: bounds)
        let path = TileGeometry.cardPath(in: rect)
        let palette = self.palette

        NSGraphicsContext.saveGraphicsState()
        if shadow {
            let dropShadow = NSShadow()
            dropShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: SystemAppearance.shared.isDark ? 0.55 : 0.28)
            dropShadow.shadowBlurRadius = rect.width * 0.06
            dropShadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.022)
            dropShadow.set()
        }
        palette.card.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        palette.cardEdge.setStroke()
        path.lineWidth = max(1, rect.width * 0.008)
        path.stroke()
        return rect
    }
}
