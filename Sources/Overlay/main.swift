import AppKit

/// The agent that draws the bar-shaped widgets over the Dock.
///
/// It needs Accessibility to read where the Dock put its tiles; it reads no
/// window contents. Each bar hides itself when its anchor is not in the Dock,
/// so the agent can simply build them all and let them decide.
final class OverlayAgentDelegate: NSObject, NSApplicationDelegate {
    private var bars: [OverlayBarController] = []
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            forName: OverlayBarController.stopNotification, object: nil, queue: .main
        ) { _ in
            NSApp.terminate(nil)
        }

        guard !isDuplicate else {
            NSApp.terminate(nil)
            return
        }

        if DockAccessibility.isTrusted {
            startBars()
        } else {
            DockAccessibility.requestTrust()
            Diagnostics.write("barra in attesa del permesso di accessibilità")
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
                guard DockAccessibility.isTrusted else { return }
                timer.invalidate()
                self?.startBars()
            }
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
        }
    }

    private func startBars() {
        let nowPlaying = BarView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        let playback = NowPlayingSource.shared.addListener { [weak nowPlaying] state in
            nowPlaying?.state = state
        }
        playbackToken = playback
        nowPlaying.onCommand = { NowPlayingFeed.send($0) }
        nowPlaying.onOpenPlayer = { openCurrentPlayer() }

        let actions = ActionsBarView(frame: NSRect(x: 0, y: 0, width: 120, height: 50))
        actions.onRun = { ActionRunner.run($0) }

        bars = [
            OverlayBarController(spec: BarLayout.nowPlaying, content: nowPlaying) {
                // In tile mode the plug-in draws the tile and the overlay would
                // cover it.
                NowPlayingSettings.current.mode == .bar
            },
            OverlayBarController(spec: BarLayout.actions, content: actions),
        ]
        bars.forEach { $0.start() }
    }

    private var playbackToken: UUID?

    func applicationWillTerminate(_ notification: Notification) {
        bars.forEach { $0.stop() }
    }

    private var isDuplicate: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1
    }
}

private func openCurrentPlayer() {
    guard let bundleID = NowPlayingSource.shared.state.playerBundleID,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
}

let application = NSApplication.shared
let delegate = OverlayAgentDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
