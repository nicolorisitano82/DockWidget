import AppKit

/// Keeps a borderless panel glued to the Dock's spacer tiles.
final class OverlayBarController {
    static let stopNotification = Notification.Name("dev.nicolo.dockwidgets.barShouldStop")

    private let spec: BarLayout.Spec
    private let content: BarContentView
    private let isEnabled: () -> Bool
    private let panel: NSPanel
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var cachedElements: [AXUIElement] = []
    private var lastResolve = Date.distantPast
    private var lastFrame = CGRect.zero

    init(spec: BarLayout.Spec, content: BarContentView, isEnabled: @escaping () -> Bool = { true }) {
        self.spec = spec
        self.content = content
        self.isEnabled = isEnabled
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        // Just above the Dock's own window, and present on every Space.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = content
    }

    func start() {
        settingsObserver = SettingsStore.shared.observeChanges { [weak self] in
            self?.content.reloadSettings()
            self?.invalidateElements()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.invalidateElements() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.invalidateElements() }

        setCadence(.warm)
        Diagnostics.write("barra \(spec.id) avviata")
    }

    func stop() {
        timer?.invalidate()
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
        panel.orderOut(nil)
    }

    // MARK: Geometry

    private func invalidateElements() {
        cachedElements = []
    }

    /// Walking the Dock's item list costs far more than reading two attributes,
    /// so the elements are resolved once and reused until the layout changes.
    private func resolveElements() {
        let items = DockAccessibility.barElements(anchorTitle: spec.anchorTitle,
                                                  spacerCount: spec.spacerCount)
        cachedElements = items.map(\.element)
        lastResolve = Date()
    }

    private func currentFrame() -> CGRect? {
        if cachedElements.isEmpty || Date().timeIntervalSince(lastResolve) > 5 {
            resolveElements()
        }
        guard !cachedElements.isEmpty else { return nil }

        content.tileCount = cachedElements.count
        let frames = cachedElements.compactMap(DockAccessibility.frame)
        guard frames.count == cachedElements.count, let first = frames.first else {
            // A stale element means the Dock relaunched or the tiles changed.
            invalidateElements()
            return nil
        }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return DockAccessibility.flipped(union)
    }

    private enum Cadence {
        /// The pointer is near the Dock: magnification moves every tile.
        case hot
        /// The bar is on screen but nothing is moving fast.
        case warm
        /// No anchor in the Dock — this copy of the widget is not in use.
        case idle
    }

    private var cadence: Cadence = .warm

    private func setCadence(_ next: Cadence) {
        guard next != cadence || timer == nil else { return }
        cadence = next
        timer?.invalidate()
        let interval: TimeInterval
        switch next {
        case .hot: interval = 1.0 / 60
        case .warm: interval = 1.0 / 6
        case .idle: interval = 2
        }
        let hot = next == .hot
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = hot ? 0 : interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isEnabled(), let frame = currentFrame(), frame.width > 20, frame.height > 10 else {
            if panel.isVisible { panel.orderOut(nil) }
            setCadence(.idle)
            return
        }

        if frame != lastFrame {
            lastFrame = frame
            panel.setFrame(frame, display: false)
            content.needsDisplay = true
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let pointer = NSEvent.mouseLocation
        let band = frame.insetBy(dx: -frame.height * 6, dy: -frame.height * 1.5)
        setCadence(band.contains(pointer) ? .hot : .warm)
    }

}
