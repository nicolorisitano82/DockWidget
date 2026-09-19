import AppKit
import ServiceManagement

/// Starts and stops the overlay agent that draws the wide bar.
enum BarAgent {
    static let identifier = "dev.nicolo.dockwidgets.bar"

    static var url: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
            .appendingPathComponent("NowPlayingBar.app", isDirectory: true)
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
    }

    static func start() {
        let executable = url.appendingPathComponent("Contents/MacOS/NowPlayingBar")
        guard FileManager.default.fileExists(atPath: executable.path) else { return }

        // Spawned as a child process rather than launched through
        // LaunchServices: a child inherits its parent's TCC responsibility, so
        // the bar works under the Accessibility consent the user gave to this
        // app instead of asking for a second one of its own.
        let task = Process()
        task.executableURL = executable
        do {
            try task.run()
        } catch {
            Diagnostics.write("avvio della barra non riuscito: \(error.localizedDescription)")
            return
        }

        // Best effort: an ad-hoc signature is not always enough for the
        // login-item registry, and the bar still works for this session.
        do {
            try SMAppService.loginItem(identifier: identifier).register()
        } catch {
            Diagnostics.write("registrazione come elemento di login non riuscita: \(error.localizedDescription)")
        }
    }

    static func stop() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.nicolo.dockwidgets.barShouldStop"), object: nil, userInfo: nil, deliverImmediately: true
        )
        try? SMAppService.loginItem(identifier: identifier).unregister()
    }
}
