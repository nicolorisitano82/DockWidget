import AppKit

/// Folders the Dock keeps as its own: the entries in `persistent-others` that
/// it opens as a fan, a grid or a list.
///
/// The folder widget can be either its own tile — drawn by our plug-in, with
/// the count and the colour — or one of these, in which case the Dock does the
/// opening, with the animation and the polish that are Apple's and that no
/// panel of ours will ever match.
enum DockStacks {
    static let key = "persistent-others"

    static func entries() -> [[String: Any]] {
        (UserDefaults(suiteName: "com.apple.dock")?.array(forKey: key) as? [[String: Any]]) ?? []
    }

    static func write(_ entries: [[String: Any]]) {
        UserDefaults(suiteName: "com.apple.dock")?.set(entries, forKey: key)
    }

    static func url(of entry: [String: Any]) -> URL? {
        guard let data = entry["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let text = file["_CFURLString"] as? String else { return nil }
        return URL(string: text)
    }

    static func contains(_ folder: URL) -> Bool {
        entries().contains { matches($0, folder) }
    }

    private static func matches(_ entry: [String: Any], _ folder: URL) -> Bool {
        guard let found = url(of: entry) else { return false }
        return found.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == folder.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Puts the folder in the Dock, or brings the one already there in line
    /// with these settings.
    ///
    /// The bookmark the Dock keeps beside the path is left out: it rebuilds it
    /// from the path, and a stale one of our making would be worse than none.
    static func set(_ folder: URL, view: FolderStack.View, sort: FolderStack.Sort, display: FolderStack.Display) {
        var list = entries()
        let tile: [String: Any] = [
            "tile-type": "directory-tile",
            "tile-data": [
                "file-data": [
                    "_CFURLString": folder.absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-label": folder.lastPathComponent,
                "file-type": 2,
                "showas": view.code,
                "arrangement": sort.code,
                "displayas": display.code,
                "preferreditemsize": -1,
            ],
        ]
        if let index = list.firstIndex(where: { matches($0, folder) }) {
            list[index] = tile
        } else {
            list.append(tile)
        }
        write(list)
    }

    static func remove(_ folder: URL) {
        let list = entries()
        let remaining = list.filter { !matches($0, folder) }
        guard remaining.count != list.count else { return }
        write(remaining)
    }
}
