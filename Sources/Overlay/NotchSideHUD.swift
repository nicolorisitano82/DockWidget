import AppKit

/// A level — brightness or volume — drawn inside the notch panel, in the black
/// band beside the notch itself.
///
/// It is part of the panel, not a window of its own: it appears when the notch
/// opens and goes with it when it closes, and the pointer resting on it is the
/// pointer resting on the panel. Closed it is a readout — a symbol and a short
/// bar. Clicked, the bar thickens into something you can drag, and goes back to
/// a readout when you leave it alone.
final class SideHUDView: NSView {
    let side: NotchSide

    private(set) var kind: NotchLevelKind = .none
    private var level: CGFloat = 0
    private var isMuted = false
    private var isExpanded = false
    private var isScrubbing = false
    private var ticker: Timer?
    private var collapseWork: DispatchWorkItem?

    init(side: NotchSide) {
        self.side = side
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("the notch is only ever built in code") }

    /// The panel never becomes key, so without this the first click is spent
    /// activating it and the second is the one that does anything.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Settings

    /// Re-reads what this side is meant to show, and hides itself when that is
    /// nothing — or when this Mac will not say what its brightness is.
    func applySettings() {
        kind = NotchSettings.current.level(on: side)
        var wanted = kind != .none
        if kind == .brightness, SystemLevels.Brightness.level == nil {
            Diagnostics.once("hud-brightness", "luminosità non leggibile: livello non mostrato")
            wanted = false
        }
        isHidden = !wanted
        collapse()
        needsDisplay = true
    }

    // MARK: Following the level

    /// Called when the notch opens.
    func begin() {
        guard !isHidden else { return }
        refresh()
        stop()
        // The level changes from the keyboard, from Control Centre, from other
        // apps: a second keeps the readout honest and costs nothing.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// And when it closes.
    func stop() {
        ticker?.invalidate()
        ticker = nil
        collapse()
    }

    private func refresh() {
        guard !isScrubbing, let value = read() else { return }
        let muted = currentMute
        guard abs(value - level) > 0.002 || muted != isMuted else { return }
        level = value
        isMuted = muted
        needsDisplay = true
    }

    private var currentMute: Bool {
        kind == .volume && (SystemLevels.Volume.isMuted ?? false)
    }

    private func read() -> CGFloat? {
        switch kind {
        case .none: return nil
        case .volume: return SystemLevels.Volume.level.map { CGFloat($0) }
        case .brightness: return SystemLevels.Brightness.level.map { CGFloat($0) }
        }
    }

    private func write(_ value: CGFloat) {
        let clamped = min(max(value, 0), 1)
        switch kind {
        case .none: return
        case .volume: SystemLevels.Volume.set(Float(clamped))
        case .brightness: SystemLevels.Brightness.set(Float(clamped))
        }
        level = clamped
        isMuted = currentMute
        needsDisplay = true
        if isExpanded { scheduleCollapse() }
    }

    // MARK: Opening the slider

    private func expand() {
        isExpanded = true
        needsDisplay = true
        scheduleCollapse()
    }

    private func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard isExpanded else { return }
        isExpanded = false
        needsDisplay = true
    }

    /// The slider puts itself away: there is no room up here for something that
    /// stays open, and a readout is what this is for most of the time.
    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    // MARK: Drawing

    /// Held off the rounded corner of the screen on the outer side, and off the
    /// notch on the inner one.
    private var content: NSRect {
        let outer: CGFloat = 14
        let inner: CGFloat = 10
        return NSRect(x: bounds.minX + (side == .left ? outer : inner),
                      y: bounds.minY,
                      width: max(bounds.width - outer - inner, 1),
                      height: bounds.height)
    }

    private var symbolBox: NSRect {
        let plot = content
        let size = min(plot.height * 0.42, 15)
        return NSRect(x: plot.minX, y: plot.midY - size / 2, width: size, height: size)
    }

    private var track: NSRect {
        let plot = content
        let height: CGFloat = isExpanded ? 9 : 4
        let left = symbolBox.maxX + 7
        return NSRect(x: left, y: plot.midY - height / 2,
                      width: max(plot.maxX - left, 1), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard kind != .none else { return }
        Gauge.symbol(isMuted ? "speaker.slash.fill" : kind.symbol,
                     in: symbolBox, color: .white)

        let bar = track
        guard bar.width > 6 else { return }
        let radius = bar.height / 2
        NSColor(calibratedWhite: 1, alpha: isExpanded ? 0.26 : 0.22).setFill()
        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

        let shown = isMuted ? 0 : level
        let width = isExpanded ? max(bar.width * shown, bar.height) : bar.width * shown
        guard width > 0.5 else { return }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY,
                                         width: width, height: bar.height),
                     xRadius: radius, yRadius: radius).fill()
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        guard kind != .none else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Open, the bar is the control; closed, anywhere on the readout opens it.
        if isExpanded, track.insetBy(dx: -6, dy: -10).contains(point) {
            isScrubbing = true
            scrub(to: point)
            return
        }
        expand()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isScrubbing else { return }
        scrub(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        isScrubbing = false
        if isExpanded { scheduleCollapse() }
    }

    /// One turn of the wheel moves it by the configured step, so the readout is
    /// useful without opening anything.
    override func scrollWheel(with event: NSEvent) {
        guard kind != .none else { return }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        guard abs(delta) > 0.1 else { return }
        let step = max(NotchSettings.current.levelStep, 0.01)
        write(level + (delta > 0 ? CGFloat(step) : -CGFloat(step)))
    }

    private func scrub(to point: NSPoint) {
        let bar = track
        guard bar.width > 0 else { return }
        write((point.x - bar.minX) / bar.width)
    }
}
