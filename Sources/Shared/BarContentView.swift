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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BarContentView is only ever built in code") }

    /// Which copy of the widget this view draws. Empty means the first one.
    var instance: String = "" {
        didSet { if instance != oldValue { reloadSettings() } }
    }

    /// The instance to read settings for, falling back to the kind itself.
    func resolvedInstance(_ kind: String) -> String { instance.isEmpty ? kind : instance }

    func reloadSettings() {}

    /// One Dock cell's width, which is the icon size the Dock is using.
    var tileWidth: CGFloat { bounds.width / CGFloat(max(tileCount, 1)) }

    /// The plate minus a margin: content that touches the panel's edge reads
    /// as content that overflowed it.
    var contentPlate: NSRect { plate.insetBy(dx: plate.height * 0.13, dy: 0) }

    /// How big a round control or a square cell should be.
    ///
    /// Measured from the tile rather than from the bar, so a three-tile bar and
    /// a six-tile one put the same size of control next to the Dock's icons.
    var controlSide: CGFloat { tileWidth * 0.56 }

    /// The space between controls, at the same scale.
    var controlGap: CGFloat { tileWidth * 0.12 }

    /// The band the neighbouring icons occupy: same height, same centre line.
    var plate: NSRect {
        // Never taller than the box it is drawn in: in the Dock the width
        // decides, in the notch the height does.
        let iconSide = min(tileWidth * TileGeometry.artworkSideRatio, bounds.height * 0.88)
        return NSRect(x: bounds.minX + (tileWidth - iconSide) / 2,
                      y: bounds.midY - iconSide / 2,
                      width: bounds.width - (tileWidth - iconSide),
                      height: iconSide)
    }
}
