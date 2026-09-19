import AppKit

/// A Dock tile plug-in that draws nothing at all.
///
/// A bar widget's tile is only an anchor for the overlay drawn on top of it.
/// Without a plug-in the Dock draws the helper app's icon there, and it shows
/// through the gaps between the bar's cells.
@objc(BlankDockTilePlugin)
final class BlankDockTilePlugin: TilePlugin {
    override func makeTileView() -> TileView {
        TileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }
}
