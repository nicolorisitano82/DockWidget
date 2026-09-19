import AppKit

final class NowPlayingTileView: TileView {
    var state = NowPlayingState() {
        didSet { needsDisplay = true }
    }

    private var settings = NowPlayingSettings.current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        accent = settings.accent
    }

    override func reloadSettings() {
        settings = NowPlayingSettings.current
        accent = settings.accent
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // In bar mode this tile is only an anchor for the overlay, which draws
        // over it: anything here would show through underneath.
        guard settings.mode == .tile else { return }
        let palette = self.palette
        let card = TileGeometry.artworkRect(in: bounds)
        let path = TileGeometry.cardPath(in: card)

        let coverArt = settings.showsArtwork && state.hasCoverArt ? state.artwork : nil

        if let coverArt {
            NSGraphicsContext.saveGraphicsState()
            let dropShadow = NSShadow()
            dropShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: SystemAppearance.shared.isDark ? 0.55 : 0.3)
            dropShadow.shadowBlurRadius = card.width * 0.06
            dropShadow.shadowOffset = NSSize(width: 0, height: -card.width * 0.022)
            dropShadow.set()
            palette.card.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            coverArt.draw(in: aspectFillRect(for: coverArt.size, in: card), from: .zero,
                          operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            drawCard()
            drawPlaceholder(in: card)
        }

        if state.hasTrack, !state.isPlaying, settings.dimsWhenPaused {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColor(calibratedWhite: 0, alpha: coverArt == nil ? 0.18 : 0.42).setFill()
            card.fill()
            NSGraphicsContext.restoreGraphicsState()
            drawSymbol("pause.fill", in: centeredSquare(in: card, ratio: 0.34),
                       color: coverArt == nil ? palette.secondary : NSColor(calibratedWhite: 1, alpha: 0.95),
                       shadowed: coverArt != nil)
        }

        if settings.showsProgress, let progress = state.progress() {
            drawProgressBar(progress, in: card, overArtwork: coverArt != nil)
        }

        path.lineWidth = max(1, card.width * 0.008)
        palette.cardEdge.setStroke()
        path.stroke()
    }

    // MARK: Pieces

    private func drawPlaceholder(in card: NSRect) {
        let palette = self.palette
        if state.hasTrack, let icon = state.artwork {
            // Broadcast channel: no album art, so the player's own icon stands in.
            let box = centeredSquare(in: card, ratio: 0.62)
            icon.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        } else {
            drawSymbol("music.note", in: centeredSquare(in: card, ratio: 0.42),
                       color: palette.secondary.withAlphaComponent(0.75))
        }
    }

    private func drawProgressBar(_ progress: Double, in card: NSRect, overArtwork: Bool) {
        let inset = card.width * 0.11
        let height = max(2, card.width * 0.052)
        let track = NSRect(x: card.minX + inset, y: card.minY + card.height * 0.095,
                           width: card.width - inset * 2, height: height)

        if overArtwork {
            // A scrim keeps the bar readable on a bright cover.
            NSGraphicsContext.saveGraphicsState()
            TileGeometry.cardPath(in: card).addClip()
            let scrim = NSGradient(colors: [NSColor(calibratedWhite: 0, alpha: 0.55),
                                            NSColor(calibratedWhite: 0, alpha: 0)])
            scrim?.draw(in: NSRect(x: card.minX, y: card.minY, width: card.width, height: card.height * 0.34),
                        angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }

        let radius = height / 2
        let trackColor = overArtwork ? NSColor(calibratedWhite: 1, alpha: 0.32) : palette.faint
        trackColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let filledWidth = max(height, track.width * CGFloat(progress))
        let filled = NSRect(x: track.minX, y: track.minY, width: filledWidth, height: height)
        palette.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor, shadowed: Bool = false) {
        if shadowed {
            // A cover can be any colour; a soft shadow keeps the glyph's edge.
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let glow = NSShadow()
            glow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.6)
            glow.shadowBlurRadius = rect.height * 0.25
            glow.shadowOffset = .zero
            glow.set()
            drawSymbol(name, in: rect, color: color)
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            let fallback = "♪" as NSString
            fallback.drawCentered(in: rect, attributes: [
                .font: NSFont.systemFont(ofSize: rect.height * 0.9, weight: .bold),
                .foregroundColor: color,
            ])
            return
        }
        let size = image.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let box = NSRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                         width: size.width * scale, height: size.height * scale)
        image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func centeredSquare(in rect: NSRect, ratio: CGFloat) -> NSRect {
        let side = min(rect.width, rect.height) * ratio
        return NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    private func aspectFillRect(for imageSize: NSSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
