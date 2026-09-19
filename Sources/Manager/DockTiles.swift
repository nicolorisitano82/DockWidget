import AppKit

/// Reads and edits the Dock's pinned items.
///
/// The Dock only re-reads its preferences when it launches, so every change
/// here ends with a restart — there is no gentler door.
enum DockTiles {
    static let domain = "com.apple.dock"
    static let key = "persistent-apps"

    static var defaults: UserDefaults? { UserDefaults(suiteName: domain) }

    static func entries() -> [[String: Any]] {
        defaults?.array(forKey: key) as? [[String: Any]] ?? []
    }

    static func write(_ entries: [[String: Any]], restart: Bool) {
        defaults?.set(entries, forKey: key)
        defaults?.synchronize()
        if restart { restartDock() }
    }

    static func url(of entry: [String: Any]) -> URL? {
        guard let tile = entry["tile-data"] as? [String: Any],
              let fileData = tile["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String else { return nil }
        return URL(string: string)
    }

    /// Whether an entry is this widget's tile.
    ///
    /// Three signals, because the Dock rewrites its entries when the user drags
    /// a tile somewhere else and matching one exact string is how a widget ends
    /// up impossible to remove afterwards.
    static func entry(_ entry: [String: Any], belongsTo widget: WidgetDescriptor) -> Bool {
        let tile = entry["tile-data"] as? [String: Any] ?? [:]

        if let identifier = tile["bundle-identifier"] as? String, identifier == widget.bundleID {
            return true
        }
        guard let url = url(of: entry) else { return false }
        let path = url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let wanted = widget.helperURL.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == wanted { return true }
        // Same widget, app moved: Applications, a build folder, a disk image.
        return path.hasSuffix("Contents/Library/Widgets/\(widget.helperBundleName)")
    }

    static func contains(_ widget: WidgetDescriptor) -> Bool {
        entries().contains { self.entry($0, belongsTo: widget) }
    }

    static func add(_ widget: WidgetDescriptor, restart: Bool = true) {
        guard !contains(widget) else { return }
        var list = entries()
        list.append([
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": [
                    "_CFURLString": widget.helperURL.absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-type": 41,
                "bundle-identifier": widget.bundleID,
            ],
        ])
        write(list, restart: restart)
    }

    static func remove(_ widget: WidgetDescriptor, restart: Bool = true) {
        let list = entries()
        let remaining = list.filter { !entry($0, belongsTo: widget) }
        guard remaining.count != list.count else { return }
        write(remaining, restart: restart)
    }

    static func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
