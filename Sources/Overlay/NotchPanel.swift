import AppKit

/// A panel that lives in the notch and opens when the pointer arrives.
///
/// Closed, it is exactly the notch: a window over a piece of screen that shows
/// nothing anyway, so it takes no space from the menu bar. Open, it grows
/// downward into a slab of glass with square top corners, so it reads as the
/// notch itself having stretched rather than as a window that appeared under it.
final class NotchPanel: NSObject {
    private let panel: NSPanel
    private let glass = NSVisualEffectView()
    private let content = NotchContentView()
    private var collapsedFrame = NSRect.zero
    private var isOpen = false
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

        glass.material = .hudWindow
        glass.state = .active
        glass.blendingMode = .behindWindow
        glass.wantsLayer = true
        glass.layer?.masksToBounds = true
        glass.autoresizingMask = [.width, .height]
        glass.addSubview(content)

        panel.contentView = glass
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
            shape(radius: 0)
        }
        panel.orderFrontRegardless()
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
        } else if isOpen, !panel.frame.insetBy(dx: -12, dy: -12).contains(point) {
            scheduleClose()
        }
    }

    private func open() {
        closeWork?.cancel()
        guard !isOpen, let screen = NotchGeometry.screen else { return }
        isOpen = true

        let settings = NotchSettings.current
        let width = max(settings.expandedWidth, collapsedFrame.width + 120)
        let height = CGFloat(max(content.rowCount, 1)) * NotchContentView.rowHeight + 22
        let frame = NSRect(x: collapsedFrame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)

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
            self?.shape(radius: 0)
        }
    }

    /// Square at the top, round at the bottom: the shape the notch would have
    /// if it could stretch.
    private func shape(radius: CGFloat) {
        glass.layer?.cornerRadius = radius
        glass.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

/// The widgets inside the notch, one row each.
final class NotchContentView: NSView {
    static let rowHeight: CGFloat = 52

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
            row.frame = NSRect(x: 12, y: bounds.height - CGFloat(index + 1) * Self.rowHeight - 8,
                               width: bounds.width - 24, height: Self.rowHeight)
        }
    }
}
