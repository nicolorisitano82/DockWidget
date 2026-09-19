import AppKit

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: ManagerViewController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController { [weak self] widget in
            self?.showWindow(selecting: widget)
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

        WidgetInstaller.restoreAfterQuit()
        reconcileBar()

        if let index = requestedWidgetIndex() {
            controller.select(index)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Bringing the manager up is the natural moment to put the bar back the
    /// way it should be: the agent dies with a logout or a crash, and the run of
    /// empty tiles can end up the wrong length — a stored width below the
    /// widget's minimum, or tiles the user dragged out.
    private func reconcileBar() {
        let mode = NowPlayingSettings.current.mode
        guard let widget = WidgetCatalog.widget(id: "nowplaying") else { return }
        Diagnostics.write("reconcile: modo \(mode.rawValue), nel dock \(widget.isInstalled), agent \(BarAgent.isRunning)")
        guard mode == .bar, widget.isInstalled else { return }

        // Spacers can end up in the wrong place or the wrong number: dragged
        // around, or a width the user lowered below the widget's minimum.
        let wanted = BarLayout.nowPlaying.spacerCount
        if !DockSpacers.isArranged(count: wanted, ownedBy: widget.id, after: widget) {
            DockSpacers.arrange(count: wanted, ownedBy: widget.id, after: widget)
        }
        if !BarAgent.isRunning {
            BarAgent.start()
        }
    }

    /// `--widget <id>`, passed when a widget's tile is clicked in the Dock.
    private func requestedWidgetIndex() -> Int? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--widget"), flag + 1 < arguments.count else { return nil }
        let id = arguments[flag + 1]
        return WidgetCatalog.all.firstIndex { $0.id == id }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow(selecting: nil)
        return true
    }

    /// Closing the window leaves the menu-bar item behind; this app has no
    /// Dock tile to go back to.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showWindow(selecting widget: WidgetDescriptor?) {
        if let widget, let index = WidgetCatalog.all.firstIndex(where: { $0.id == widget.id }) {
            controller?.select(index)
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
