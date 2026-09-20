import AppKit

/// The empty Dock tiles a bar widget is drawn over.
///
/// Every spacer we create carries our own key inside its tile-data, and the
/// Dock keeps it — until the Dock itself rewrites that entry, which it does
/// whenever it saves its own state. Then the key is gone and the spacer looks
/// like any other.
///
/// So the mark is a hint, not an identity: what actually makes a spacer ours
/// is sitting in the run immediately after the widget's tile. The cost of that
/// is a spacer of the user's own, placed right there, being swept up with
/// ours — and the price of the alternative was re-laying the spacers on every
/// launch, which means restarting the Dock on every launch.
enum DockSpacers {
    static let ownerKey = "underdock-owner"

    private static func owner(of entry: [String: Any]) -> String? {
        guard (entry["tile-type"] as? String)?.hasSuffix("spacer-tile") ?? false,
              let tile = entry["tile-data"] as? [String: Any] else { return nil }
        return tile[ownerKey] as? String
    }

    private static func spacer(ownedBy id: String) -> [String: Any] {
        ["tile-type": "spacer-tile", "tile-data": [ownerKey: id]]
    }

    /// The spacers sitting right after the widget's tile, ours by position.
    static func countAdjacent(to widget: WidgetDescriptor) -> Int {
        let list = DockTiles.entries()
        guard let anchor = list.firstIndex(where: { DockTiles.entry($0, belongsTo: widget) }) else {
            return 0
        }
        return list[(anchor + 1)...].prefix(while: isSpacer).count
    }

    /// True when exactly `count` of our spacers sit right after the widget,
    /// which is the only arrangement the overlay can line itself up with.
    static func isArranged(count: Int, ownedBy id: String, after widget: WidgetDescriptor) -> Bool {
        let list = DockTiles.entries()
        guard list.contains(where: { DockTiles.entry($0, belongsTo: widget) }) else {
            return count == 0
        }
        return countAdjacent(to: widget) == count
    }

    /// Removes every spacer of ours and lays `count` of them right after the
    /// widget's tile.
    static func arrange(count: Int, ownedBy id: String, after widget: WidgetDescriptor) {
        var list = DockTiles.entries().filter { owner(of: $0) != id }
        // Unmarked spacers left by an older version, right where ours go.
        if let anchor = list.firstIndex(where: { DockTiles.entry($0, belongsTo: widget) }) {
            var end = anchor + 1
            while end < list.count, isSpacer(list[end]) { end += 1 }
            list.removeSubrange((anchor + 1)..<end)
        }
        if count > 0, let anchor = list.firstIndex(where: { DockTiles.entry($0, belongsTo: widget) }) {
            list.insert(contentsOf: Array(repeating: spacer(ownedBy: id), count: count), at: anchor + 1)
        }
        DockTiles.write(list)
    }

    /// Takes out every spacer of ours, plus — when the widget is given — the
    /// run of spacers sitting right after its tile.
    ///
    /// That second sweep is for spacers made before they carried a marker:
    /// without it they stay in the Dock forever, with nothing left to say whose
    /// they were.
    static func removeAll(ownedBy id: String, adjacentTo widget: WidgetDescriptor? = nil) {
        var list = DockTiles.entries()
        let before = list.count

        if let widget, let anchor = list.firstIndex(where: { DockTiles.entry($0, belongsTo: widget) }) {
            var end = anchor + 1
            while end < list.count, isSpacer(list[end]) { end += 1 }
            list.removeSubrange((anchor + 1)..<end)
        }
        list = list.filter { owner(of: $0) != id }

        guard list.count != before else { return }
        DockTiles.write(list)
    }

    private static func isSpacer(_ entry: [String: Any]) -> Bool {
        (entry["tile-type"] as? String)?.hasSuffix("spacer-tile") ?? false
    }
}
