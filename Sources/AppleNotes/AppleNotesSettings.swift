import AppKit

struct AppleNotesSettings: Equatable {
    enum Mode: String, CaseIterable {
        case tile, bar
        var label: String { self == .tile ? T("Standard", "Standard") : T("Barra", "Bar") }
    }

    var mode: Mode = .tile
    /// Empty means every folder.
    var folder = ""
    var showsSnippet = true
    var accentHex = "#FFD60A"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemYellow }

    enum Key {
        static func mode(_ instance: String) -> String { "\(instance).mode" }
        static func folder(_ instance: String) -> String { "\(instance).folder" }
        static func showsSnippet(_ instance: String) -> String { "\(instance).showsSnippet" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: AppleNotesSettings { current("applenotes") }

    static func current(_ instance: String) -> AppleNotesSettings {
        let store = SettingsStore.shared
        let defaults = AppleNotesSettings()
        return AppleNotesSettings(
            mode: Mode(rawValue: store.string(Key.mode(instance), or: defaults.mode.rawValue))
                ?? defaults.mode,
            folder: store.string(Key.folder(instance), or: defaults.folder),
            showsSnippet: store.bool(Key.showsSnippet(instance), or: defaults.showsSnippet),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "applenotes") {
        SettingsStore.shared.set([
            Key.mode(instance): mode.rawValue,
            Key.folder(instance): folder,
            Key.showsSnippet(instance): showsSnippet,
            Key.accent(instance): accentHex,
        ])
    }
}
