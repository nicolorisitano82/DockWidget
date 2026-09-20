import AppKit

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: ManagerViewController?
    private var statusItem: StatusItemController?
    private var selectionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController { [weak self] instance in
            self?.showWindow(selecting: instance)
        }

        // A click on a widget's tile arrives here. The manager can be running
        // with no window at all — it lives in the menu bar — so selecting the
        // widget is not enough: the window has to come back.
        selectionObserver = DistributedNotificationCenter.default().addObserver(
            forName: .selectWidget, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.object as? String else { return }
            self?.showWindow(selecting: id)
        }

        let controller = ManagerViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Dock Widgets"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.controller = controller

        SettingsStore.shared.migrate(prefix: "nowPlaying.", to: "nowplaying.")
        InstanceFactory.refreshAll()
        WidgetInstaller.restoreAfterQuit()
        reconcileBars()

        if let requested = requestedWidget() {
            controller.select(instance: requested)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Bringing the manager up is the natural moment to put the bars back the
    /// way they should be: the agent dies with a logout or a crash, and a run
    /// of empty tiles can end up the wrong length or in the wrong place.
    ///
    /// The Dock is only restarted when something actually has to change — a
    /// transaction costs the user a Dock restart.
    private func reconcileBars() {
        var repairs: [() -> Void] = []
        var needsAgent = false

        for widget in WidgetCatalog.all {
            guard widget.isInstalled, let spec = widget.barSpec else {
                // A widget that went back to being a tile leaves its spacers
                // behind, and they are recognised by sitting next to it.
                if DockSpacers.countAdjacent(to: widget) > 0 {
                    repairs.append {
                        DockSpacers.removeAll(ownedBy: widget.id, adjacentTo: widget)
                    }
                }
                continue
            }
            needsAgent = true
            if !DockSpacers.isArranged(count: spec.spacerCount, ownedBy: widget.id, after: widget) {
                repairs.append {
                    DockSpacers.arrange(count: spec.spacerCount, ownedBy: widget.id, after: widget)
                }
            }
        }

        if !repairs.isEmpty {
            DockTiles.transaction { repairs.forEach { $0() } }
        }
        // The notch panel lives in the same agent as the bars.
        if needsAgent || NotchSettings.current.isEnabled, !BarAgent.isRunning {
            BarAgent.start()
        }
    }

    /// `--widget <id>`, passed when a widget's tile is clicked in the Dock.
    private func requestedWidget() -> String? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--widget"), flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow(selecting: nil)
        return true
    }

    /// Closing the window leaves the menu-bar item behind; this app has no
    /// Dock tile to go back to.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showWindow(selecting instance: String?) {
        if let instance {
            controller?.select(instance: instance)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

if let flag = CommandLine.arguments.firstIndex(of: "--probe-dock") {
    let reportPath = flag + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[flag + 1]
        : NSTemporaryDirectory() + "dockprobe.txt"
    _ = NSApplication.shared
    DockProbe.run(reportPath: reportPath)
    exit(0)
}

let application = NSApplication.shared
let delegate = ManagerAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
