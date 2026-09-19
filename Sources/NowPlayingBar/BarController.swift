import AppKit

/// Keeps a borderless panel glued to the Dock's spacer tiles.
final class BarController {
    static let stopNotification = Notification.Name("dev.nicolo.dockwidgets.barShouldStop")

    private let panel: NSPanel
    private let barView: BarView
    private var timer: Timer?
    private var isHot = false
    private var listenerToken: UUID?
    private var cachedElements: [AXUIElement] = []
    private var lastResolve = Date.distantPast
    private var lastFrame = CGRect.zero

    init() {
        barView = BarView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        panel = NSPanel(contentRect: barView.frame,
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
        panel.contentView = barView

        barView.onCommand = { command in NowPlayingFeed.send(command) }
        barView.onOpenPlayer = { [weak self] in self?.openPlayer() }
    }

    func start() {
        listenerToken = NowPlayingSource.shared.addListener { [weak self] state in
            self?.barView.state = state
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

        setCadence(hot: false)
        Diagnostics.write("barra avviata")
    }

    func stop() {
        timer?.invalidate()
        if let listenerToken {
            NowPlayingSource.shared.removeListener(listenerToken)
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
        let spec = BarLayout.nowPlaying
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

        barView.tileCount = cachedElements.count
        let frames = cachedElements.compactMap(DockAccessibility.frame)
        guard frames.count == cachedElements.count, let first = frames.first else {
            // A stale element means the Dock relaunched or the tiles changed.
            invalidateElements()
            return nil
        }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return DockAccessibility.flipped(union)
    }

    private func setCadence(hot: Bool) {
        guard hot != isHot || timer == nil else { return }
        isHot = hot
        timer?.invalidate()
        // 60 Hz while the pointer is near the Dock, because magnification moves
        // every tile under it; a lazy beat the rest of the time.
        let interval: TimeInterval = hot ? 1.0 / 60 : 1.0 / 6
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = hot ? 0 : interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let frame = currentFrame(), frame.width > 20, frame.height > 10 else {
            if panel.isVisible { panel.orderOut(nil) }
            setCadence(hot: false)
            return
        }

        if frame != lastFrame {
            lastFrame = frame
            panel.setFrame(frame, display: false)
            barView.needsDisplay = true
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let pointer = NSEvent.mouseLocation
        let band = frame.insetBy(dx: -frame.height * 6, dy: -frame.height * 1.5)
        setCadence(hot: band.contains(pointer))
    }

    private func openPlayer() {
        guard let bundleID = NowPlayingSource.shared.state.playerBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
