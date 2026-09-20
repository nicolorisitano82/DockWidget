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
        content.autoresizingMask = [.width, .height]
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
        content.reload(instances: settings.widgets)
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
    }

    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
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

    var rowCount: Int { rows.count }

    func reload(instances: [String]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = instances.compactMap { NotchWidgets.view(for: $0) }
        rows.forEach(addSubview)
        layout()
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
