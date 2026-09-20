import Foundation

/// Italian and English, without bundles.
///
/// The project assembles four bundles by hand — the manager, the agent and a
/// plug-in per widget — and each would need its own .lproj to use the normal
/// machinery. For two languages that is more plumbing than text, so a string
/// carries both and picks at the point of use.
func T(_ italian: String, _ english: String) -> String {
    Localization.isItalian ? italian : english
}

enum Localization {
    static let isItalian: Bool = {
        guard let preferred = Locale.preferredLanguages.first else { return false }
        return preferred.hasPrefix("it")
    }()
}
