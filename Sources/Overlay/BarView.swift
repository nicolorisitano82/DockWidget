import AppKit

/// The wide, interactive now-playing bar drawn over the Dock's spacer tiles.
///
/// Every measurement is a fraction of the view's height, because that height is
/// whatever the Dock says right now: the bar grows and shrinks with the
/// magnification of the icons beside it.
final class BarView: BarContentView {
    var state = NowPlayingState() {
        didSet { needsDisplay = true }
    }

    /// What the pointer is over, and what it is holding down. A control that
    /// does not answer the pointer feels broken, so both are drawn.
    private enum Target: Equatable {
        case previous, playPause, next, artwork, progress
    }

    private var hovered: Target? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    private var pressed: Target? {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }

    var onCommand: ((NowPlayingFeed.Command) -> Void)?
    var onOpenPlayer: (() -> Void)?

    override func reloadSettings() {
        needsDisplay = true
    }

    private var palette: TilePalette {
        TilePalette.resolve(dark: isDarkContext,
                            accent: NowPlayingSettings.current(resolvedInstance("nowplaying")).accent)
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

        init(plate: NSRect, controlSide: CGFloat, gap: CGFloat) {
            self.plate = plate

            let padding = plate.height * 0.10
            let content = plate.insetBy(dx: padding, dy: padding)
            let artworkSide = content.height
            artwork = NSRect(x: content.minX, y: content.minY, width: artworkSide, height: artworkSide)

            self.controlSide = min(content.height, controlSide)
            let controlsWidth = self.controlSide * 3 + gap * 2
            let controlsX = content.maxX - controlsWidth
            let controlsY = content.midY - min(content.height, controlSide) / 2
            previous = NSRect(x: controlsX, y: controlsY,
                              width: self.controlSide, height: self.controlSide)
            playPause = previous.offsetBy(dx: self.controlSide + gap, dy: 0)
            next = playPause.offsetBy(dx: self.controlSide + gap, dy: 0)

            let textX = artwork.maxX + padding
            let textWidth = max(0, controlsX - padding - textX)
            let barHeight = max(2, content.height * 0.085)
            progress = NSRect(x: textX, y: content.minY, width: textWidth, height: barHeight)
            text = NSRect(x: textX, y: progress.maxY + padding * 0.4,
                          width: textWidth, height: content.maxY - progress.maxY - padding * 0.4)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let metrics = Metrics(plate: plate, controlSide: controlSide, gap: controlGap)
        let palette = self.palette
        let dark = isDarkContext

        drawWidgetBackground()

        drawArtwork(in: metrics.artwork)

        if state.hasTrack {
            drawText(in: metrics.text, palette: palette)
            drawProgress(in: metrics.progress, palette: palette)
        } else {
            let label = T("Niente in riproduzione", "Nothing playing") as NSString
            let font = NSFont.systemFont(ofSize: max(8, metrics.text.height * 0.42), weight: .medium)
            label.draw(at: NSPoint(x: metrics.text.minX, y: metrics.text.midY - font.pointSize * 0.6),
                       withAttributes: [.font: font, .foregroundColor: palette.secondary])
        }

        drawControl("backward.fill", in: metrics.previous, target: .previous, palette: palette)
        drawControl(state.isPlaying ? "pause.fill" : "play.fill", in: metrics.playPause,
                    target: .playPause, palette: palette)
        drawControl("forward.fill", in: metrics.next, target: .next, palette: palette)
    }

    private func drawArtwork(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.22, yRadius: rect.height * 0.22)
        let palette = self.palette

        guard state.hasCoverArt, let artwork = state.artwork else {
            NSColor(calibratedWhite: isDarkContext ? 1 : 0, alpha: 0.08).setFill()
            path.fill()
            drawSymbol("music.note", in: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28),
                       color: palette.secondary)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        defer {
            NSGraphicsContext.restoreGraphicsState()
            if hovered == .artwork || pressed == .artwork {
                NSColor(calibratedWhite: pressed == .artwork ? 0 : 1,
                        alpha: pressed == .artwork ? 0.18 : 0.14).setFill()
                path.fill()
            }
        }
        let size = artwork.size
        let scale = max(rect.width / size.width, rect.height / size.height)
        let box = NSRect(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
                         width: size.width * scale, height: size.height * scale)
        artwork.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
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

    private func drawProgress(in rect0: NSRect, palette: TilePalette) {
        let isActive = hovered == .progress || pressed == .progress
        let rect = isActive ? rect0.insetBy(dx: 0, dy: -rect0.height * 0.35) : rect0
        let radius = rect.height / 2
        NSColor(calibratedWhite: isDarkContext ? 1 : 0, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        guard let progress = state.progress() else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY,
                            width: max(rect.height, rect.width * CGFloat(progress)), height: rect.height)
        palette.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()

        if isActive {
            let knob = rect.height * 1.7
            let centre = NSPoint(x: filled.maxX, y: rect.midY)
            palette.primary.setFill()
            NSBezierPath(ovalIn: NSRect(x: centre.x - knob / 2, y: centre.y - knob / 2,
                                        width: knob, height: knob)).fill()
        }
    }

    /// A control with its pointer states: a ring of background on hover, a
    /// stronger one plus a touch of shrink while held.
    private func drawControl(_ name: String, in rect: NSRect, target: Target, palette: TilePalette) {
        let isPressed = pressed == target
        let isHovered = hovered == target

        if isHovered || isPressed {
            let dark = isDarkContext
            let alpha: CGFloat = isPressed ? (dark ? 0.26 : 0.18) : (dark ? 0.14 : 0.09)
            NSColor(calibratedWhite: dark ? 1 : 0, alpha: alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        // The circle is the whole cell; the glyph sits well inside it, or the
        // two touch and the highlight reads as a smudge around the icon.
        var glyph = rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.24)
        if isPressed {
            glyph = glyph.insetBy(dx: glyph.width * 0.07, dy: glyph.height * 0.07)
        }
        drawSymbol(name, in: glyph, color: isPressed ? palette.accent : palette.primary)
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

    private func target(at point: NSPoint) -> Target? {
        let metrics = Metrics(plate: plate, controlSide: controlSide, gap: controlGap)
        let slack = metrics.controlSide * 0.12
        if metrics.playPause.insetBy(dx: -slack, dy: -slack).contains(point) { return .playPause }
        if metrics.next.insetBy(dx: -slack, dy: -slack).contains(point) { return .next }
        if metrics.previous.insetBy(dx: -slack, dy: -slack).contains(point) { return .previous }
        if metrics.progress.insetBy(dx: 0, dy: -metrics.progress.height * 1.5).contains(point) { return .progress }
        if metrics.artwork.contains(point) { return .artwork }
        return nil
    }

    private func perform(_ target: Target, at point: NSPoint) {
        switch target {
        case .playPause: onCommand?(.togglePlayPause)
        case .next: onCommand?(.next)
        case .previous: onCommand?(.previous)
        case .artwork: onOpenPlayer?()
        case .progress:
            guard let duration = state.duration else { return }
            let bar = Metrics(plate: plate, controlSide: controlSide, gap: controlGap).progress
            let fraction = min(max((point.x - bar.minX) / bar.width, 0), 1)
            onCommand?(.seek(duration * Double(fraction)))
        }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = target(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        // The highlight follows the pointer off the control and back on, the
        // way a button behaves everywhere else.
        guard pressed != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        hovered = target(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { pressed = nil }
        guard let pressed, target(at: point) == pressed else { return }
        perform(pressed, at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = target(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways because the bar never becomes the key window.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if state.hasTrack {
            let track = NSMenuItem(title: state.title ?? "", action: nil, keyEquivalent: "")
            track.isEnabled = false
            menu.addItem(track)
            menu.addItem(.separator())
        }
        let open = NSMenuItem(title: T("Apri il player", "Open the player"), action: #selector(openPlayer), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openPlayer() {
        onOpenPlayer?()
    }
}
