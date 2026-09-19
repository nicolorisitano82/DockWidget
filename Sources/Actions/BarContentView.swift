import AppKit

/// Base for anything drawn over a run of Dock tiles.
///
/// The Dock decides the size, and it changes constantly as icons magnify, so a
/// content view is told how many tiles it spans and measures everything from
/// its own bounds.
class BarContentView: NSView {
    /// Anchor tile plus its spacers.
    var tileCount: Int = 2 {
        didSet { if tileCount != oldValue { needsDisplay = true } }
    }

    func reloadSettings() {}

    /// One Dock cell's width, which is the icon size the Dock is using.
    var tileWidth: CGFloat { bounds.width / CGFloat(max(tileCount, 1)) }

    /// The band the neighbouring icons occupy: same height, same centre line.
    var plate: NSRect {
        let iconSide = tileWidth * TileGeometry.artworkSideRatio
        return NSRect(x: bounds.minX + (tileWidth - iconSide) / 2,
                      y: bounds.midY - iconSide / 2,
                      width: bounds.width - (tileWidth - iconSide),
                      height: iconSide)
    }
}
