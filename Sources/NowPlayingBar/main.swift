import AppKit

/// The agent that draws the now-playing bar over the Dock.
///
/// It needs Accessibility to read where the Dock put its tiles; it reads no
/// window contents and posts no events.
final class BarAgentDelegate: NSObject, NSApplicationDelegate {
    private let controller = BarController()
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            forName: BarController.stopNotification, object: nil, queue: .main
        ) { _ in
            NSApp.terminate(nil)
        }

        guard !isDuplicate else {
            NSApp.terminate(nil)
            return
        }

        if DockAccessibility.isTrusted {
            controller.start()
        } else {
            DockAccessibility.requestTrust()
            Diagnostics.write("barra in attesa del permesso di accessibilità")
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
                guard DockAccessibility.isTrusted else { return }
                timer.invalidate()
                self?.controller.start()
            }
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private var isDuplicate: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1
    }
}

let application = NSApplication.shared
let delegate = BarAgentDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
