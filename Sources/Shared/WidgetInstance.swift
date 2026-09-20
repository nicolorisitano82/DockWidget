import Foundation

/// A widget can exist more than once: two clocks on different time zones, two
/// folders watching different places.
///
/// Each copy is its own app bundle — the Dock gives one tile per application —
/// and its own set of settings. The instance identifier is the prefix of both:
/// the first copy of a kind keeps the bare kind ("clock"), so nothing written
/// before instances existed has to move.
enum WidgetInstance {
    /// How many copies of each widget the build makes available.
    static let maximumCopies = 3

    static func id(kind: String, copy: Int) -> String {
        copy <= 1 ? kind : "\(kind)\(copy)"
    }

    static func kind(of instance: String) -> String {
        String(instance.reversed().drop { $0.isNumber }.reversed())
    }

    static func copy(of instance: String) -> Int {
        let digits = instance.reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? 1
    }

    static func all(of kind: String) -> [String] {
        (1...maximumCopies).map { id(kind: kind, copy: $0) }
    }

    /// The bundle the build produces for a copy: "Orologio.app", "Orologio 2.app".
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
}

extension SettingsStore {
    /// Settings keys are prefixed with the instance, so "clock2.style" sits
    /// beside "clock.style" without either knowing about the other.
    static func key(_ name: String, for instance: String) -> String {
        "\(instance).\(name)"
    }
}
