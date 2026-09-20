import Foundation

/// A widget can exist as many times as you want it to: two clocks on different
/// time zones, three folders watching three places.
///
/// Each copy is its own app bundle — the Dock gives one tile per application —
/// and its own set of settings. The instance identifier is the prefix of both:
/// the first copy of a kind keeps the bare kind ("clock"), so nothing written
/// before copies existed has to move.
enum WidgetInstance {
    static func id(kind: String, copy: Int) -> String {
        copy <= 1 ? kind : "\(kind)\(copy)"
    }

    /// A widget placed in the notch is another instance of it, with settings
    /// of its own: the notch is a different place with different room, and the
    /// same clock wants to look different there.
    static let notchSuffix = "@notch"

    static func notchID(kind: String) -> String { kind + notchSuffix }

    static func isNotch(_ instance: String) -> Bool { instance.hasSuffix(notchSuffix) }

    private static func base(_ instance: String) -> String {
        instance.components(separatedBy: notchSuffix).first ?? instance
    }

    static func kind(of instance: String) -> String {
        String(base(instance).reversed().drop { $0.isNumber }.reversed())
    }

    static func copy(of instance: String) -> Int {
        let digits = base(instance).reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? 1
    }

    /// The bundle a copy lives in: "Orologio.app", "Orologio 2.app".
    static func bundleName(base: String, copy: Int) -> String {
        copy <= 1 ? "\(base).app" : "\(base) \(copy).app"
    }

    /// What the Dock calls the tile — the bundle's file name without the
    /// extension — which is also what the overlay anchors to.
    static func anchorTitle(base: String, copy: Int) -> String {
        copy <= 1 ? base : "\(base) \(copy)"
    }

    /// The instance a plug-in belongs to, read from its own bundle identifier.
    static func fromBundleIdentifier(_ identifier: String?) -> String {
        (identifier ?? "").components(separatedBy: ".")
            .last(where: { !$0.isEmpty && $0 != "tile" }) ?? ""
    }

    /// Where copies beyond the first are kept.
    ///
    /// Not inside the app: the app is replaced wholesale on every update, and
    /// the Dock would find its tiles pointing at bundles that vanished.
    static var copiesDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/DockWidgets/Widgets",
                                    isDirectory: true)
    }
}

/// Which copies of each widget exist, kept with the settings so that every
/// process — manager, agent, plug-ins — sees the same list.
enum WidgetInstances {
    static func key(_ kind: String) -> String { "instances.\(kind)" }

    /// Always starts with the bare kind: the first copy is the one the app
    /// ships with and cannot be removed.
    static func all(of kind: String) -> [String] {
        let stored = SettingsStore.shared.strings(key(kind)) ?? []
        let extras = stored.filter { $0 != kind && WidgetInstance.kind(of: $0) == kind }
        return [kind] + extras.sorted { WidgetInstance.copy(of: $0) < WidgetInstance.copy(of: $1) }
    }

    /// Adds the next copy and returns its identifier.
    @discardableResult
    static func add(to kind: String) -> String {
        let used = Set(all(of: kind).map(WidgetInstance.copy))
        var next = 2
        while used.contains(next) { next += 1 }

        let instance = WidgetInstance.id(kind: kind, copy: next)
        var stored = SettingsStore.shared.strings(key(kind)) ?? []
        stored.append(instance)
        SettingsStore.shared.set(stored, for: key(kind))
        return instance
    }

    static func remove(_ instance: String) {
        let kind = WidgetInstance.kind(of: instance)
        let stored = (SettingsStore.shared.strings(key(kind)) ?? []).filter { $0 != instance }
        SettingsStore.shared.set(stored, for: key(kind))
    }

    /// Every copy of every widget that has a bar, for the agent to draw.
    static func all(ofKinds kinds: [String]) -> [String] {
        kinds.flatMap { all(of: $0) }
    }
}
