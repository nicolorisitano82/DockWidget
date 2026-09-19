import AppKit

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: ManagerViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = ManagerViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Dock Widgets"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.controller = controller

        if let index = requestedWidgetIndex() {
            controller.select(index)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `--widget <id>`, passed when a widget's tile is clicked in the Dock.
    private func requestedWidgetIndex() -> Int? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--widget"), flag + 1 < arguments.count else { return nil }
        let id = arguments[flag + 1]
        return WidgetCatalog.all.firstIndex { $0.id == id }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = ManagerAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
