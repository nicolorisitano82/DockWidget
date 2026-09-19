import AppKit

/// Inserts and removes the empty Dock tiles the overlay bar is drawn over.
///
/// The Dock reserves the space and keeps doing the layout, magnification and
/// auto-hide; we only have to follow it.
enum DockSpacers {
    private static let domain = "com.apple.dock"
    private static let key = "persistent-apps"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: domain) }

    private static func entries() -> [[String: Any]] {
        defaults?.array(forKey: key) as? [[String: Any]] ?? []
    }

    private static func isSpacer(_ entry: [String: Any]) -> Bool {
        (entry["tile-type"] as? String)?.hasSuffix("spacer-tile") ?? false
    }

    private static func indexOfAnchor(_ appURL: URL, in entries: [[String: Any]]) -> Int? {
        let wanted = appURL.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return entries.firstIndex { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let fileData = tile["file-data"] as? [String: Any],
                  let string = fileData["_CFURLString"] as? String,
                  let url = URL(string: string) else { return false }
            return url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == wanted
        }
    }

    /// How many of our spacers currently sit right after the anchor.
    static func count(after appURL: URL) -> Int {
        let list = entries()
        guard let anchor = indexOfAnchor(appURL, in: list) else { return 0 }
        var index = anchor + 1
        var found = 0
        while index < list.count, isSpacer(list[index]) {
            found += 1
            index += 1
        }
        return found
    }

    /// Makes the run right after the anchor exactly `count` spacers long.
    static func set(count: Int, after appURL: URL, restart: Bool = true) {
        guard let defaults else { return }
        var list = entries()
        guard let anchor = indexOfAnchor(appURL, in: list) else { return }

        var end = anchor + 1
        while end < list.count, isSpacer(list[end]) { end += 1 }
        list.removeSubrange((anchor + 1)..<end)

        let spacer: [String: Any] = ["tile-type": "spacer-tile", "tile-data": [:]]
        list.insert(contentsOf: Array(repeating: spacer, count: max(0, count)), at: anchor + 1)

        defaults.set(list, forKey: key)
        defaults.synchronize()
        if restart { DockTiles.restartDock() }
    }
}
