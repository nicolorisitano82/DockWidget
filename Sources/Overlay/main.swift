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
        var playbackTokens: [UUID] = []

        let kinds: [BarWidgetKind] = [
            BarWidgetKind(base: "NowPlaying", template: BarLayout.nowPlaying, makeView: { instance in
                let view = BarView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
                view.onCommand = { NowPlayingFeed.send($0) }
                view.onOpenPlayer = { openCurrentPlayer() }
                playbackTokens.append(NowPlayingSource.shared.addListener { [weak view] state in
                    view?.state = state
                })
                return view
            }, isEnabled: { NowPlayingSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Azioni", template: BarLayout.actions, makeView: { _ in
                let view = ActionsBarView(frame: NSRect(x: 0, y: 0, width: 120, height: 50))
                view.onRun = { ActionRunner.run($0) }
                return view
            }, isEnabled: { _ in true }),

            BarWidgetKind(base: "Sensori", template: BarLayout.sensors, makeView: { _ in
                SensorsBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
            }, isEnabled: { SensorsSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Dischi", template: BarLayout.disks, makeView: { _ in
                DisksBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
            }, isEnabled: { DisksSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Appunto", template: BarLayout.note, makeView: { instance in
                let view = NoteBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
                view.onEdit = { [weak view] in
                    guard let window = view?.window else { return }
                    noteEditor.toggle(above: window.frame, instance: instance)
                }
                return view
            }, isEnabled: { _ in true }),
        ]

        bars = kinds.flatMap { $0.controllers(playback: &playbackTokens) }
        self.playbackTokens = playbackTokens
        bars.forEach { $0.start() }
    }

    private var playbackTokens: [UUID] = []

    func applicationWillTerminate(_ notification: Notification) {
        bars.forEach { $0.stop() }
    }

    private var isDuplicate: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1
    }
}

private let noteEditor = NoteEditorPanel()

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
