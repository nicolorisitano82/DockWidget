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
    private let slab = NSView()
    private let content = NotchContentView()
    private var collapsedFrame = NSRect.zero
    private var isOpen = false
    private var openFrame = NSRect.zero
    private var closeWork: DispatchWorkItem?
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
        slab.layer?.backgroundColor = NSColor.black.cgColor
        slab.layer?.masksToBounds = true
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
        content.apply(instances: settings.widgets)
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
        if trigger.contains(point) {
            open()
        } else if isOpen, !openFrame.insetBy(dx: -10, dy: -10).contains(point) {
            // The pointer has left the panel's own area: the frame it is
            // animating towards, not the one it happens to have this instant.
            scheduleClose()
        }
    }

    private func open() {
        closeWork?.cancel()
        closeWork = nil
        guard !isOpen, let screen = NotchGeometry.screen else { return }
        isOpen = true
        panel.setFrame(collapsedFrame, display: false)
        panel.orderFrontRegardless()

        let settings = NotchSettings.current
        let width = max(settings.expandedWidth, collapsedFrame.width + 120)
        // The first row starts below the notch itself, or it would sit beside
        // the camera housing where nothing can be read.
        content.topInset = collapsedFrame.height + 6
        let height = content.topInset
            + CGFloat(max(content.rowCount, 1)) * NotchContentView.rowHeight + 12
        let frame = NSRect(x: collapsedFrame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)

        openFrame = frame
        shape(radius: 22)
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
        let work = DispatchWorkItem { [weak self] in
            self?.closeWork = nil
            self?.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
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

    /// Square at the top, round at the bottom: the shape the notch would have
    /// if it could stretch.
    private func shape(radius: CGFloat) {
        slab.layer?.cornerRadius = radius
        slab.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

/// The widgets inside the notch, one row each.
final class NotchContentView: NSView {
    static let rowHeight: CGFloat = 52

    /// How far down the first row starts: the height of the notch, so the
    /// content clears it.
    var topInset: CGFloat = 32 {
        didSet { needsLayout = true }
    }

    private var rows: [BarContentView] = []
    private var shown: [String] = []
    private var beat: Timer?

    var rowCount: Int { rows.count }

    /// Builds the rows when the chosen widgets change, and otherwise just lets
    /// the ones already there re-read their settings: rebuilding on every
    /// change would leak a listener each time.
    func apply(instances: [String]) {
        guard instances != shown else {
            rows.forEach { $0.reloadSettings() }
            return
        }
        shown = instances
        rows.forEach { $0.removeFromSuperview() }
        rows = instances.compactMap { NotchWidgets.view(for: $0) }
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
    }

    func stopBeating() {
        beat?.invalidate()
        beat = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 14,
                               y: bounds.height - topInset - CGFloat(index + 1) * Self.rowHeight,
                               width: bounds.width - 28, height: Self.rowHeight)
        }
    }
}
