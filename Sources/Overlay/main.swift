import AppKit

/// The agent that draws the bar-shaped widgets over the Dock.
///
/// It needs Accessibility to read where the Dock put its tiles; it reads no
/// window contents. Each bar hides itself when its anchor is not in the Dock,
/// so the agent can simply build them all and let them decide.
final class OverlayAgentDelegate: NSObject, NSApplicationDelegate {
    private var bars: [OverlayBarController] = []
    private let notch = NotchPanel()
    private var previewObserver: NSObjectProtocol?
    private var openObserver: NSObjectProtocol?
    private var dropObserver: NSObjectProtocol?
    private var signals: [DispatchSourceSignal] = []
    private var pointerTimer: Timer?
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

    /// Holds the now-playing listeners while the views are being built.
    private final class TokenBag {
        var tokens: [UUID] = []
    }

    private func startBars() {
        let bag = TokenBag()

        let kinds: [BarWidgetKind] = [
            BarWidgetKind(base: "NowPlaying", template: BarLayout.nowPlaying, makeView: { instance in
                let view = BarView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
                view.onCommand = { NowPlayingControl.send($0) }
                view.onOpenPlayer = { openCurrentPlayer() }
                bag.tokens.append(NowPlayingSource.shared.addListener { [weak view] state in
                    view?.state = state
                })
                return view
            }, isEnabled: { NowPlayingSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Azioni", template: BarLayout.actions, makeView: { _ in
                let view = ActionsBarView(frame: NSRect(x: 0, y: 0, width: 120, height: 50))
                view.onRun = { runAction($0) }
                return view
            }, isEnabled: { _ in true }),

            BarWidgetKind(base: "Sensori", template: BarLayout.sensors, makeView: { _ in
                SensorsBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
            }, isEnabled: { SensorsSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Dischi", template: BarLayout.disks, makeView: { _ in
                DisksBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
            }, isEnabled: { DisksSettings.current($0).mode == .bar }),

            BarWidgetKind(base: "Appuntamenti", template: BarLayout.calendar, makeView: { _ in
                let view = CalendarBarView(frame: NSRect(x: 0, y: 0, width: 220, height: 50))
                view.onOpen = {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                return view
            }, isEnabled: { _ in true }),

            BarWidgetKind(base: "Meteo", template: BarLayout.weather, makeView: { _ in
                WeatherBarView(frame: NSRect(x: 0, y: 0, width: 180, height: 50))
            }, isEnabled: { _ in true }),

            BarWidgetKind(base: "Mensola", template: BarLayout.shelf, makeView: { _ in
                let view = ShelfBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
                view.onOpen = { NSWorkspace.shared.open($0) }
                return view
            }, isEnabled: { _ in true }),

            BarWidgetKind(base: "Appunto", template: BarLayout.note, makeView: { instance in
                let view = NoteBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
                view.onEdit = { [weak view] in
                    guard let window = view?.window else { return }
                    noteEditor.toggle(above: window.frame, instance: instance)
                }
                return view
            }, isEnabled: { _ in true }),
        ]

        bars = kinds.flatMap { $0.controllers() }
        playbackTokens = bag.tokens
        bars.forEach { $0.start() }

        // A click on a folder tile asks for its preview; the tile's own helper
        // has quit by the time this arrives.
        previewObserver = DistributedNotificationCenter.default().addObserver(
            forName: WidgetClick.previewRequested, object: nil, queue: .main
        ) { note in
            guard let instance = note.object as? String else { return }
            folderPreview.toggle(instance: instance)
        }

        // If a previous run ended with the preview open, the Dock is still
        // without its magnification: it gets it back.
        DockFreeze.restoreIfNeeded()
        watchForTermination()
        FolderReader.restoreGrants()

        openObserver = DistributedNotificationCenter.default().addObserver(
            forName: WidgetClick.openRequested, object: nil, queue: .main
        ) { note in
            guard let path = note.object as? String else { return }
            Diagnostics.write("apro su richiesta di una tile: \(path)")
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }


        dropObserver = DistributedNotificationCenter.default().addObserver(
            forName: WidgetClick.dropRequested, object: nil, queue: .main
        ) { note in
            // The instance first, then a path a line.
            let parts = (note.object as? String)?.components(separatedBy: "\n") ?? []
            guard let instance = parts.first, parts.count > 1 else { return }
            let files = parts.dropFirst().map { URL(fileURLWithPath: $0) }
            Diagnostics.write("drop su \(instance): \(files.count) elementi")
            folderPreview.drop(instance: instance, files: Array(files))
        }

        notch.start()
        // The notch has no tracking area of its own while it is closed: a
        // window that catches the pointer up there would swallow the menu
        // bar's own hovering. So the pointer is watched instead, gently.
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            self?.notch.pointerMoved(to: NSEvent.mouseLocation)
        }
        timer.tolerance = 1.0 / 24
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private var playbackTokens: [UUID] = []

    func applicationWillTerminate(_ notification: Notification) {
        bars.forEach { $0.stop() }
        pointerTimer?.invalidate()
        notch.stop()
        folderPreview.close()
        DockFreeze.release()
        mirror.close()
        for observer in [previewObserver, openObserver, dropObserver].compactMap({ $0 }) {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// A `pkill` — which is how the installer clears the way — sends SIGTERM,
    /// and that never reaches applicationWillTerminate. Without this the Dock
    /// would be left without its magnification until the manager next started.
    private func watchForTermination() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                DockFreeze.release()
                exit(0)
            }
            source.resume()
            signals.append(source)
        }
    }

    private var isDuplicate: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1
    }
}

private let noteEditor = NoteEditorPanel()
private let folderPreview = FolderPreviewPanel()
private let mirror = MirrorPanel()

/// Runs an action from inside the agent.
///
/// The mirror is a window, and the window belongs here: going through a
/// distributed notification would mean this process asking itself, which it may
/// not be awake enough to hear. Everything else goes to the shared runner.
func runAction(_ kind: ActionKind) {
    if case .mirror = kind {
        // Asked of the manager, which is a registered application and can
        // therefore be shown the camera prompt. With no manager about, this
        // tries anyway: it works wherever the permission is already given.
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "dev.nicolo.underdock").isEmpty else {
            DistributedNotificationCenter.default().postNotificationName(
                ActionRunner.mirrorRequested, object: nil, userInfo: nil,
                deliverImmediately: true)
            return
        }
        mirror.toggle()
        return
    }
    ActionRunner.run(kind)
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
