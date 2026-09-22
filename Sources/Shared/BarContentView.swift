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

    /// Inside the notch the panel is black whatever the Mac's theme is, so the
    /// content has to be drawn dark or a light theme would put white cards on
    /// a black slab.
    var forcesDarkContent = false {
        didSet { if forcesDarkContent != oldValue { needsDisplay = true } }
    }

    /// The theme this view should draw for.
    var isDarkContext: Bool { forcesDarkContent || SystemAppearance.shared.isDark }

    /// The bars and the notch live in panels that never become key, and by
    /// default the click that reaches such a window is spent activating it
    /// instead of arriving here. Every click counts.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reloadSettings() {}

    /// One Dock cell's width, which is the icon size the Dock is using.
    var tileWidth: CGFloat { bounds.width / CGFloat(max(tileCount, 1)) }

    /// How far a stacked row holds its contents off its own edge.
    static let stackedInset: CGFloat = 12

    /// The plate minus a margin: content that touches the card's edge reads as
    /// content that overflowed it.
    ///
    /// Vertically only where the rows are stacked. In the Dock the plate is the
    /// band the icons beside it occupy, and shrinking it would make the widget
    /// smaller than its neighbours; in the notch the plate is a card drawn
    /// around the contents, and contents have to stay off its edge.
    var contentPlate: NSRect {
        let inset = plate.height * 0.13
        return plate.insetBy(dx: inset, dy: fillsHeight ? inset : 0)
    }

    /// How big a round control or a square cell should be.
    ///
    /// Measured from the tile rather than from the bar, so a three-tile bar and
    /// a six-tile one put the same size of control next to the Dock's icons.
    var controlSide: CGFloat {
        fillsHeight ? plate.height * 0.62 : tileWidth * 0.56
    }

    /// The space between controls, at the same scale.
    var controlGap: CGFloat {
        fillsHeight ? plate.height * 0.14 : tileWidth * 0.12
    }

    /// How many of the notch's rows this view was given: one, or two when it
    /// has a fuller layout to put in them.
    var verticalSlots = 1 {
        didSet { if verticalSlots != oldValue { needsDisplay = true } }
    }

    /// True where every row must come out the same size whatever it contains
    /// — the notch, where the widgets are stacked and a taller one would look
    /// like a mistake.
    var fillsHeight = false {
        didSet { if fillsHeight != oldValue { needsDisplay = true } }
    }

    /// The band the neighbouring icons occupy: same height, same centre line.
    var plate: NSRect {
        // In the Dock the width of a tile decides the size, because the widget
        // has to match the icons beside it. Stacked in the notch there are no
        // icons to match, and the height is what every row shares.
        let iconSide = fillsHeight
            ? bounds.height * 0.72
            : min(tileWidth * TileGeometry.artworkSideRatio, bounds.height * 0.88)
        // Stacked rows sit flush against one another, so what separates them is
        // the margin each one keeps between its own contents and its own edge.
        guard !fillsHeight else {
            return NSRect(x: bounds.minX + Self.stackedInset,
                          y: bounds.midY - iconSide / 2,
                          width: max(bounds.width - Self.stackedInset * 2, 1),
                          height: iconSide)
        }
        return NSRect(x: bounds.minX + (tileWidth - iconSide) / 2,
                      y: bounds.midY - iconSide / 2,
                      width: bounds.width - (tileWidth - iconSide),
                      height: iconSide)
    }
}
