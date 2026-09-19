import AppKit

/// The wide, interactive now-playing bar drawn over the Dock's spacer tiles.
///
/// Every measurement is a fraction of the view's height, because that height is
/// whatever the Dock says right now: the bar grows and shrinks with the
/// magnification of the icons beside it.
final class BarView: NSView {
    var state = NowPlayingState() {
        didSet { needsDisplay = true }
    }

    /// Anchor tile plus spacers: how many Dock cells the bar covers.
    var tileCount = BarLayout.nowPlaying.spacerCount + 1

    var onCommand: ((NowPlayingFeed.Command) -> Void)?
    var onOpenPlayer: (() -> Void)?

    private var palette: TilePalette {
        TilePalette.resolve(dark: SystemAppearance.shared.isDark,
                            accent: NowPlayingSettings.current.accent)
    }

    private struct Metrics {
        let plate: NSRect
        let artwork: NSRect
        let text: NSRect
        let progress: NSRect
        let previous: NSRect
        let playPause: NSRect
        let next: NSRect
        let controlSide: CGFloat

        init(bounds: NSRect, tileCount: Int) {
            // The bar spans one anchor tile plus its spacers, all the same
            // width, so one tile's width gives the icon size the Dock is using
            // — and the bar has to be exactly that tall to sit level with the
            // icons beside it.
            let tileWidth = bounds.width / CGFloat(max(tileCount, 1))
            let iconSide = tileWidth * TileGeometry.artworkSideRatio
            let plate = NSRect(x: bounds.minX + (tileWidth - iconSide) / 2,
                               y: bounds.midY - iconSide / 2,
                               width: bounds.width - (tileWidth - iconSide),
                               height: iconSide)
            self.plate = plate

            let padding = plate.height * 0.10
            let content = plate.insetBy(dx: padding, dy: padding)
            let artworkSide = content.height
            artwork = NSRect(x: content.minX, y: content.minY, width: artworkSide, height: artworkSide)

            controlSide = content.height * 0.62
            let controlsWidth = controlSide * 3 + padding * 2
            let controlsX = content.maxX - controlsWidth
            let controlsY = content.midY - controlSide / 2
            previous = NSRect(x: controlsX, y: controlsY, width: controlSide, height: controlSide)
            playPause = previous.offsetBy(dx: controlSide + padding, dy: 0)
            next = playPause.offsetBy(dx: controlSide + padding, dy: 0)

            let textX = artwork.maxX + padding
            let textWidth = max(0, controlsX - padding - textX)
            let barHeight = max(2, content.height * 0.085)
            progress = NSRect(x: textX, y: content.minY, width: textWidth, height: barHeight)
            text = NSRect(x: textX, y: progress.maxY + padding * 0.4,
                          width: textWidth, height: content.maxY - progress.maxY - padding * 0.4)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let metrics = Metrics(bounds: bounds, tileCount: tileCount)
        let palette = self.palette
        let dark = SystemAppearance.shared.isDark

        // A faint plate: the Dock's glass is behind us and can be any colour.
        let platePath = NSBezierPath(roundedRect: metrics.plate,
                                     xRadius: metrics.plate.height * 0.26,
                                     yRadius: metrics.plate.height * 0.26)
        NSColor(calibratedWhite: dark ? 1 : 0, alpha: dark ? 0.10 : 0.06).setFill()
        platePath.fill()

        drawArtwork(in: metrics.artwork)

        if state.hasTrack {
            drawText(in: metrics.text, palette: palette)
            drawProgress(in: metrics.progress, palette: palette)
        } else {
            let label = "Niente in riproduzione" as NSString
            let font = NSFont.systemFont(ofSize: max(8, metrics.text.height * 0.42), weight: .medium)
            label.draw(at: NSPoint(x: metrics.text.minX, y: metrics.text.midY - font.pointSize * 0.6),
                       withAttributes: [.font: font, .foregroundColor: palette.secondary])
        }

        drawSymbol("backward.fill", in: metrics.previous, color: palette.primary)
        drawSymbol(state.isPlaying ? "pause.fill" : "play.fill", in: metrics.playPause, color: palette.primary)
        drawSymbol("forward.fill", in: metrics.next, color: palette.primary)
    }

    private func drawArtwork(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.22, yRadius: rect.height * 0.22)
        let palette = self.palette

        guard state.hasCoverArt, let artwork = state.artwork else {
            NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0, alpha: 0.08).setFill()
            path.fill()
            drawSymbol("music.note", in: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28),
                       color: palette.secondary)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let size = artwork.size
        let scale = max(rect.width / size.width, rect.height / size.height)
        let box = NSRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                         width: size.width * scale, height: size.height * scale)
        artwork.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(in rect: NSRect, palette: TilePalette) {
        let titleSize = max(8, rect.height * 0.52)
        let title = (state.title ?? "") as NSString
        let titleFont = NSFont.systemFont(ofSize: titleSize, weight: .semibold)
        title.draw(in: NSRect(x: rect.minX, y: rect.maxY - titleSize * 1.25,
                              width: rect.width, height: titleSize * 1.3),
                   withAttributes: [
                       .font: titleFont,
                       .foregroundColor: palette.primary,
                       .paragraphStyle: truncating,
                   ])

        guard let subtitle = state.artist, !subtitle.isEmpty else { return }
        let subtitleSize = max(7, rect.height * 0.40)
        let subtitleFont = NSFont.systemFont(ofSize: subtitleSize, weight: .regular)
        (subtitle as NSString).draw(in: NSRect(x: rect.minX, y: rect.minY,
                                               width: rect.width, height: subtitleSize * 1.3),
                                    withAttributes: [
                                        .font: subtitleFont,
                                        .foregroundColor: palette.secondary,
                                        .paragraphStyle: truncating,
                                    ])
    }

    private var truncating: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func drawProgress(in rect: NSRect, palette: TilePalette) {
        let radius = rect.height / 2
        NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        guard let progress = state.progress() else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY,
                            width: max(rect.height, rect.width * CGFloat(progress)), height: rect.height)
        palette.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.62, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let box = NSRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                         width: size.width * scale, height: size.height * scale)
        image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let metrics = Metrics(bounds: bounds, tileCount: tileCount)

        if metrics.playPause.insetBy(dx: -4, dy: -4).contains(point) {
            onCommand?(.togglePlayPause)
        } else if metrics.next.insetBy(dx: -4, dy: -4).contains(point) {
            onCommand?(.next)
        } else if metrics.previous.insetBy(dx: -4, dy: -4).contains(point) {
            onCommand?(.previous)
        } else if metrics.progress.insetBy(dx: 0, dy: -6).contains(point), let duration = state.duration {
            let fraction = min(max((point.x - metrics.progress.minX) / metrics.progress.width, 0), 1)
            onCommand?(.seek(duration * Double(fraction)))
        } else if metrics.artwork.contains(point) {
            onOpenPlayer?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if state.hasTrack {
            let track = NSMenuItem(title: state.title ?? "", action: nil, keyEquivalent: "")
            track.isEnabled = false
            menu.addItem(track)
            menu.addItem(.separator())
        }
        let open = NSMenuItem(title: "Apri il player", action: #selector(openPlayer), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openPlayer() {
        onOpenPlayer?()
    }
}
