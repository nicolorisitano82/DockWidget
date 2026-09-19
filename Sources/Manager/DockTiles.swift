import AppKit

/// Reads and edits the Dock's pinned items.
///
/// The Dock only re-reads its preferences when it launches, so every change
/// here ends with a restart — there is no gentler door.
enum DockTiles {
    private static let domain = "com.apple.dock"
    private static let key = "persistent-apps"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: domain) }

    private static func entries() -> [[String: Any]] {
        defaults?.array(forKey: key) as? [[String: Any]] ?? []
    }

    private static func url(of entry: [String: Any]) -> URL? {
        guard let tile = entry["tile-data"] as? [String: Any],
              let fileData = tile["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String else { return nil }
        return URL(string: string)
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        let trim = { (url: URL) in
            url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return trim(lhs) == trim(rhs)
    }

    static func contains(_ appURL: URL) -> Bool {
        entries().contains { url(of: $0).map { samePath($0, appURL) } ?? false }
    }

    static func add(_ appURL: URL) {
        guard let defaults, !contains(appURL) else { return }
        var list = entries()
        list.append([
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": [
                    "_CFURLString": appURL.absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-type": 41,
            ],
        ])
        defaults.set(list, forKey: key)
        defaults.synchronize()
        restartDock()
    }

    static func remove(_ appURL: URL) {
        guard let defaults else { return }
        let remaining = entries().filter { entry in
            guard let entryURL = url(of: entry) else { return true }
            return !samePath(entryURL, appURL)
        }
        guard remaining.count != entries().count else { return }
        defaults.set(remaining, forKey: key)
        defaults.synchronize()
        restartDock()
    }

    static func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
