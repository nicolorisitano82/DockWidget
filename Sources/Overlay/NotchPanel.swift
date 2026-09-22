import AppKit

/// A panel that lives in the notch and opens when the pointer arrives.
///
/// Closed, it is exactly the notch: a window over a piece of screen that shows
/// nothing anyway, so it takes no space from the menu bar. Open, it grows
/// downward into a slab of glass with square top corners, so it reads as the
/// notch itself having stretched rather than as a window that appeared under it.
final class NotchPanel: NSObject {
    private let panel: NSPanel
    /// Black, not glass. The notch and the bezel around the screen are black,
    /// and the panel is meant to read as that shape stretching — a translucent
    /// slab reads as a window that appeared underneath it instead.
    private let slab = NotchSlabView()
    private let content = NotchContentView()
    private var collapsedFrame = NSRect.zero
    private var isOpen = false
    private var openFrame = NSRect.zero
    private var closeWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    /// False right after a close, until the pointer is seen away from the notch.
    private var hasLeftSinceClose = true
    private var settingsObserver: NSObjectProtocol?

    override init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Above the menu bar, or the notch would open behind it.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle,
                                    .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true

        super.init()

        slab.wantsLayer = true
        slab.autoresizingMask = [.width, .height]
        slab.addSubview(content)

        panel.contentView = slab
        // Pinned rather than autoresized: an autoresizing mask adjusts a frame
        // as the superview grows, and this one started at zero — so the rows
        // had no area to be clicked in, and nothing they drew was ever seen.
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: slab.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: slab.trailingAnchor),
            content.topAnchor.constraint(equalTo: slab.topAnchor),
            content.bottomAnchor.constraint(equalTo: slab.bottomAnchor),
        ])
    }

    func start() {
        settingsObserver = SettingsStore.shared.observeChanges { [weak self] in
            self?.apply()
        }
        apply()
    }

    func stop() {
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
        panel.orderOut(nil)
    }

    private func apply() {
        let settings = NotchSettings.current
        guard settings.isEnabled, let screen = NotchGeometry.screen else {
            panel.orderOut(nil)
            return
        }
        collapsedFrame = NotchGeometry.rect(on: screen)
        // The band the levels sit in is the notch's own: its height, and the
        // width left either side of it once the panel has opened.
        content.bandHeight = collapsedFrame.height
        content.notchWidth = collapsedFrame.width
        content.apply(instances: settings.fittedWidgets)
        content.applyLevels()
        if !isOpen {
            panel.setFrame(collapsedFrame, display: false)
            // Hidden, not merely flush with the notch: a black rectangle over
            // the notch squares off the rounded corners the hardware has.
            panel.orderOut(nil)
        }
    }

    // MARK: Opening and closing

    /// Called by the agent's pointer watch: the panel has no tracking area of
    /// its own while closed, because a window that catches the pointer at the
    /// top of the screen would eat the menu bar's own hovering.
    func pointerMoved(to point: NSPoint) {
        guard NotchSettings.current.isEnabled, !collapsedFrame.isEmpty else { return }
        let trigger = collapsedFrame.insetBy(dx: -8, dy: -2)
        let isOnTrigger = trigger.contains(point)

        // A pointer parked on the notch must not make the panel open, close
        // and open again forever: after a close it has to leave and come back.
        if !isOnTrigger { hasLeftSinceClose = true }

        if isOnTrigger, hasLeftSinceClose {
            scheduleOpen()
        } else if !isOnTrigger {
            openWork?.cancel()
            openWork = nil
        }

        if isOpen, !openFrame.insetBy(dx: -10, dy: -10).contains(point), !isOnTrigger {
            // The pointer has left the panel's own area: the frame it is
            // animating towards, not the one it happens to have this instant.
            scheduleClose()
        }
    }

    /// Opens after the pointer has stayed put for the configured moment.
    private func scheduleOpen() {
        guard !isOpen, openWork == nil else { return }
        let delay = max(NotchSettings.current.openDelay, 0)
        guard delay > 0 else {
            open()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.openWork = nil
            self?.open()
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func open() {
        closeWork?.cancel()
        closeWork = nil
        openWork?.cancel()
        openWork = nil
        guard !isOpen, let screen = NotchGeometry.screen else { return }
        isOpen = true
        panel.setFrame(collapsedFrame, display: false)
        panel.orderFrontRegardless()

        // Wider than the content by the fillets on either side, which are
        // drawn outside it and need somewhere to be.
        let width = max(NotchSettings.expandedWidth, collapsedFrame.width + 120)
            + NotchSlabView.fillet * 2
        // The first row starts below the notch itself, or it would sit beside
        // the camera housing where nothing can be read.
        content.topInset = collapsedFrame.height + NotchContentView.topPadding
        let height = content.topInset + content.rowsHeight + NotchContentView.bottomPadding
        let frame = NSRect(x: collapsedFrame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)

        openFrame = frame
        slab.isOpen = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
        content.isHidden = false
        content.startBeating()
    }

    /// Starts the grace period once, and leaves it alone.
    ///
    /// The pointer is checked twelve times a second, so re-arming the timer on
    /// every check postponed the closing by another third of a second each
    /// time — which is to say, forever.
    private func scheduleClose() {
        guard closeWork == nil else { return }
        let delay = max(NotchSettings.current.closeDelay, 0.05)
        let work = DispatchWorkItem { [weak self] in
            self?.closeWork = nil
            self?.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
        slab.isOpen = false
        hasLeftSinceClose = false
        content.stopBeating()
        content.isHidden = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapsedFrame, display: true)
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    // The shape lives in the slab, which draws it.

}

/// The widgets inside the notch, one row each.
final class NotchContentView: NSView {
    static let rowHeight: CGFloat = 52
    /// Air between the notch and the first row, between one row and the next,
    /// and under the last one. Widgets pressed against the edges of the slab
    /// look like they were poured in rather than placed.
    static let topPadding: CGFloat = 10
    /// Zero: the rows touch, and what separates them is the margin each widget
    /// keeps between its own contents and its own edge.
    static let rowSpacing: CGFloat = 0
    static let bottomPadding: CGFloat = 12

    /// How far down the first row starts: the height of the notch, so the
    /// content clears it.
    var topInset: CGFloat = 32 {
        didSet { needsLayout = true }
    }

    /// The height of the notch, and how wide it is: the band the levels live
    /// in runs the width of the panel, and the notch takes the middle of it.
    var bandHeight: CGFloat = 32 { didSet { needsLayout = true } }
    var notchWidth: CGFloat = 200 { didSet { needsLayout = true } }

    /// A level either side of the notch. Part of the panel: they come down with
    /// it and go up with it, and there is no second window to keep in step.
    private let levels = NotchSide.allCases.map(SideHUDView.init(side:))
    /// The line of actions under the last row, when there is one.
    private let actions = NotchActionBar()

    private var rows: [BarContentView] = []
    /// One or two, per row, in the same order.
    private var spans: [Int] = []
    private var shown: [String] = []
    private var shownWidths: [Int] = []
    private var beat: Timer?

    var rowCount: Int { rows.count }

    /// What all the rows come to, spacing included — and the line of actions
    /// under them where it is shown.
    var rowsHeight: CGFloat {
        guard !spans.isEmpty else { return Self.rowHeight + actionBarHeight }
        let tall = spans.reduce(0) { $0 + CGFloat($1) } * Self.rowHeight
        return tall + CGFloat(spans.count - 1) * Self.rowSpacing + actionBarHeight
    }

    private var actionBarHeight: CGFloat {
        actions.isHidden ? 0 : NotchActionBar.height + 4
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        levels.forEach(addSubview)
        actions.onRun = { runAction($0) }
        addSubview(actions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("the notch is only ever built in code") }

    /// Re-reads which level goes on which side, and what is in the action line.
    func applyLevels() {
        levels.forEach { $0.applySettings() }
        actions.reload()
        actions.isHidden = !NotchSettings.current.showsActionBar || actions.isEmpty
        Diagnostics.once("actionbar-\(actions.isHidden)-\(actions.count)",
                         "striscia azioni: \(actions.count) celle, nascosta=\(actions.isHidden)")
        needsLayout = true
    }

    /// Builds the rows when the chosen widgets change, and otherwise just lets
    /// the ones already there re-read their settings: rebuilding on every
    /// change would leak a listener each time.
    func apply(instances: [String]) {
        // The height a row takes is part of what it is: growing one to two
        // rows has to rebuild the panel, not just redraw it.
        let widths = instances.map { NotchWidgets.cellCount(for: $0) }
        let heights = instances.map { NotchSettings.span(of: $0) }
        guard instances != shown || widths != shownWidths || heights != spans else {
            rows.forEach { $0.reloadSettings() }
            return
        }
        shownWidths = widths
        shown = instances
        rows.forEach { $0.removeFromSuperview() }
        rows = instances.compactMap { NotchWidgets.view(for: $0) }
        spans = instances.compactMap { NotchWidgets.view(for: $0) == nil ? nil : NotchSettings.span(of: $0) }
        rows.forEach(addSubview)
        needsLayout = true
    }

    /// A beat while the panel is open.
    ///
    /// In the Dock each bar has a controller that redraws it; here there is
    /// none, so a progress bar would sit still between one track and the next.
    func startBeating() {
        stopBeating()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.rows.forEach { $0.needsDisplay = true }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        beat = timer
        levels.forEach { $0.begin() }
    }

    func stopBeating() {
        beat?.invalidate()
        beat = nil
        levels.forEach { $0.stop() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Either side of the notch, in the band the notch itself occupies.
        let sideWidth = max((bounds.width - notchWidth) / 2, 0)
        for view in levels {
            // Too narrow to read is worse than absent.
            guard sideWidth >= 56 else {
                view.frame = .zero
                continue
            }
            view.frame = NSRect(x: view.side == .left ? 0 : bounds.width - sideWidth,
                                y: bounds.height - bandHeight,
                                width: sideWidth, height: bandHeight)
        }

        var top = topInset
        defer {
            // Under everything, across the whole width, centred by the view.
            actions.frame = NSRect(x: 0, y: bounds.height - top - NotchActionBar.height,
                                   width: bounds.width, height: NotchActionBar.height)
        }
        for (index, row) in rows.enumerated() {
            let span = index < spans.count ? spans[index] : 1
            let height = CGFloat(span) * Self.rowHeight
            let side = 16 + NotchSlabView.fillet
            row.frame = NSRect(x: side, y: bounds.height - top - height,
                               width: bounds.width - side * 2, height: height)
            top += height + Self.rowSpacing
        }
        top += 4
    }
}


/// The black shape the panel is.
///
/// Square across the top, round at the bottom, and — where the top meets the
/// menu bar on either side — the concave fillet the hardware notch has, so the
/// panel reads as that shape having stretched rather than as a rectangle laid
/// over it.
final class NotchSlabView: NSView {
    /// How far the fillet reaches sideways into the menu bar.
    static let fillet: CGFloat = 12
    /// The corner at the bottom, which is convex like any panel's.
    static let corner: CGFloat = 22

    var isOpen = false {
        didSet { if isOpen != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillet = Self.fillet
        let corner = Self.corner
        let body = bounds
        let path = NSBezierPath()

        // Down the left side from under the fillet, round the bottom, and up
        // the right to meet its own fillet.
        path.move(to: NSPoint(x: body.minX + fillet, y: body.maxY))
        path.line(to: NSPoint(x: body.minX + fillet, y: body.minY + corner))
        path.appendArc(withCenter: NSPoint(x: body.minX + fillet + corner, y: body.minY + corner),
                       radius: corner, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: body.maxX - fillet - corner, y: body.minY))
        path.appendArc(withCenter: NSPoint(x: body.maxX - fillet - corner, y: body.minY + corner),
                       radius: corner, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: body.maxX - fillet, y: body.maxY))
        path.close()

        NSColor.black.setFill()
        path.fill()

        guard isOpen else { return }
        // The two fillets, where the panel's edge meets the top of the screen.
        // Each is the sliver between the panel's own edge and a quarter circle
        // centred outside it, level with the foot of the curve: the arc itself
        // is the black's outer boundary, so the edge flares open as it climbs
        // rather than stepping out and leaving a corner behind.
        for onLeft in [true, false] {
            let outer = onLeft ? body.minX : body.maxX
            let inner = onLeft ? body.minX + fillet : body.maxX - fillet
            let curve = NSBezierPath()
            curve.move(to: NSPoint(x: inner, y: body.maxY))
            curve.line(to: NSPoint(x: outer, y: body.maxY))
            curve.appendArc(withCenter: NSPoint(x: outer, y: body.maxY - fillet),
                            radius: fillet,
                            startAngle: 90,
                            endAngle: onLeft ? 0 : 180,
                            clockwise: onLeft)
            curve.close()
            NSColor.black.setFill()
            curve.fill()
        }
    }

}
