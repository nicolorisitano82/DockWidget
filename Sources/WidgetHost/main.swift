import AppKit

/// A widget's app bundle exists so the Dock has something to pin and a plug-in
/// to load. It has no interface of its own: a click on the tile brings up the
/// manager, and files dropped on the tile are handed to the widget's own
/// handling.
final class WidgetHostDelegate: NSObject, NSApplicationDelegate {
    private var handledDrop = false

    private var widgetID: String {
        (Bundle.main.bundleIdentifier ?? "").components(separatedBy: ".").last ?? ""
    }

    /// …/DockWidgets.app/Contents/Library/Widgets/<Widget>.app → …/DockWidgets.app
    private var managerURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledDrop = WidgetDrop.handle(widgetID: widgetID, files: urls)
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dropped files arrive just after launch, so a plain click is only
        // recognised once that moment has passed without any.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard !handledDrop else {
                NSApp.terminate(nil)
                return
            }
            openManager()
        }
    }

    private func openManager() {
        // If the manager is already up, launch arguments would be ignored.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.nicolo.dockwidgets.selectWidget"),
            object: widgetID, userInfo: nil, deliverImmediately: true
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["--widget", widgetID]
        NSWorkspace.shared.openApplication(at: managerURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        // Never outlive the request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { NSApp.terminate(nil) }
    }
}

let application = NSApplication.shared
let delegate = WidgetHostDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
