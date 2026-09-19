import AppKit

// A widget's app bundle exists so the Dock has something to pin and a plug-in to
// load. It is an agent (no Dock tile of its own, no menu bar), and all it does
// when its tile is clicked is bring up the manager on the right widget.

let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
let widgetID = bundleIdentifier.components(separatedBy: ".").last ?? ""

// …/DockWidgets.app/Contents/Library/Widgets/<Widget>.app → …/DockWidgets.app
let managerURL = Bundle.main.bundleURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

// If the manager is already up, launch arguments would be ignored — tell it directly.
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("dev.nicolo.dockwidgets.selectWidget"),
    object: widgetID, userInfo: nil, deliverImmediately: true
)

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.arguments = ["--widget", widgetID]
NSWorkspace.shared.openApplication(at: managerURL, configuration: configuration) { _, _ in
    exit(0)
}

// Never outlive the request.
RunLoop.main.run(until: Date().addingTimeInterval(5))
exit(0)
