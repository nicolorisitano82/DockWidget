import AppKit
import ServiceManagement

/// Starts and stops the overlay agent that draws the wide bar.
enum BarAgent {
    static let identifier = "dev.nicolo.underdock.bar"

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
            Diagnostics.write("barra generata come processo figlio, pid \(task.processIdentifier)")
        } catch {
            Diagnostics.write("avvio della barra non riuscito: \(error.localizedDescription)")
            return
        }

        // Deliberately not registered as a login item of its own: launchd
        // would start a second copy, and macOS kills a registered helper that
        // anything but launchd launched — a Launch Constraint Violation. The
        // manager opens at login instead, and starts the bar from there.
    }

    static func stop() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.nicolo.underdock.barShouldStop"), object: nil, userInfo: nil, deliverImmediately: true
        )
        try? SMAppService.loginItem(identifier: identifier).unregister()
    }
}
