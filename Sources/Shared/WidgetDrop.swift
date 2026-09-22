import AppKit

/// What a widget does with files dropped on its Dock tile.
///
/// Drag and drop reaches the helper app, not the plug-in — the Dock delivers
/// dropped files to the application that owns the tile — so the handling lives
/// here, where the helper can reach it without linking a widget's whole code.
enum WidgetDrop {
    /// Returns true when the files were dealt with, so the helper knows not to
    /// treat the launch as a plain click.
    @discardableResult
    static func handle(widgetID: String, files: [URL]) -> Bool {
        // The kind decides what to do; the identifier itself is the settings
        // prefix, so a second folder drops into its own folder and a second
        // shelf keeps its own files.
        switch WidgetInstance.kind(of: widgetID) {
        case "folder":
            // Not moved where the widget happens to point: dropping something
            // is a question — into this folder, or into one of the folders
            // inside it — and the answer is the user's. The panel that asks is
            // the agent's, which is also the one that can put a window up.
            let path = SettingsStore.shared.string("\(widgetID).path", or: "")
            guard !path.isEmpty else { return false }
            DistributedNotificationCenter.default().postNotificationName(
                WidgetClick.dropRequested,
                object: ([widgetID] + files.map(\.path)).joined(separator: "\n"),
                userInfo: nil, deliverImmediately: true)
            return true
        case "shelf":
            // Nothing is moved: the shelf keeps where the file is.
            let key = "\(widgetID).paths"
            var stored = SettingsStore.shared.strings(key) ?? []
            let incoming = files.map(\.path)
            stored = Array((incoming + stored.filter { !incoming.contains($0) }).prefix(12))
            SettingsStore.shared.set(stored, for: key)
            return true
        default:
            return false
        }
    }
}

/// What a widget does when its tile is clicked.
///
/// The default is to bring up the manager on that widget, but some widgets have
/// something better to do: clicking a folder should open the folder, not ask
/// you about it. Settings stay one right-click away.
enum WidgetClick {
    /// Sent when a tile wants its preview shown, carrying the instance.
    static let previewRequested = Notification.Name("dev.nicolo.underdock.previewRequested")

    /// Sent when files are dropped on a folder tile: the widget asks where
    /// they should go rather than deciding for itself.
    static let dropRequested = Notification.Name("dev.nicolo.underdock.dropRequested")

    /// Sent when something chosen inside a tile's menu has to be opened,
    /// carrying the path. The menu is built by the plug-in, which lives inside
    /// the Dock's host and is in no position to open anything itself.
    static let openRequested = Notification.Name("dev.nicolo.underdock.openRequested")

    /// Opens a file, from wherever there is a process allowed to.
    ///
    /// The request always goes out. Asking first whether anyone is listening
    /// was the mistake: inside the Dock's plug-in host — a sandboxed service —
    /// `NSRunningApplication` sees no other applications at all, so the answer
    /// was always "nobody", and the fallback it fell back to is precisely the
    /// call that sandbox refuses. Posting costs nothing and crosses the fence.
    static func requestOpen(_ url: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            openRequested, object: url.path, userInfo: nil, deliverImmediately: true)
    }

    /// Returns true when the click was dealt with here.
    @discardableResult
    static func handle(widgetID: String) -> Bool {
        switch WidgetInstance.kind(of: widgetID) {
        case "folder":
            let path = SettingsStore.shared.string("\(widgetID).path", or: "")
            guard !path.isEmpty else { return false }
            // The preview is drawn by the bar agent: it is the process that is
            // already there, already allowed to ask the Dock where its tiles
            // are, and already in the business of putting panels on screen.
            // This one is about to quit.
            guard SettingsStore.shared.string("\(widgetID).click", or: "preview") == "preview" else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return true
            }
            DistributedNotificationCenter.default().postNotificationName(
                WidgetClick.previewRequested, object: widgetID, userInfo: nil,
                deliverImmediately: true)
            return true
        default:
            return false
        }
    }
}
