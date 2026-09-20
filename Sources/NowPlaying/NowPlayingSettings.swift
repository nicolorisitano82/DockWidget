import AppKit

struct NowPlayingSettings: Equatable {
    enum Mode: String, CaseIterable {
        /// A square Dock tile drawn by the plug-in.
        case tile
        /// A wide interactive bar drawn by the agent over spacer tiles.
        case bar

        var label: String { self == .tile ? "Tile" : T("Barra", "Bar") }
    }

    var mode: Mode = .tile
    var showsArtwork = true
    var showsProgress = true
    var dimsWhenPaused = true
    var accentHex = "#0A84FF"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static func mode(_ instance: String) -> String { "\(instance).mode" }
        static func showsArtwork(_ instance: String) -> String { "\(instance).showsArtwork" }
        static func showsProgress(_ instance: String) -> String { "\(instance).showsProgress" }
        static func dimsWhenPaused(_ instance: String) -> String { "\(instance).dimsWhenPaused" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: NowPlayingSettings { current("nowPlaying") }

    static func current(_ instance: String) -> NowPlayingSettings {
        let store = SettingsStore.shared
        let defaults = NowPlayingSettings()
        return NowPlayingSettings(
            mode: Mode(rawValue: store.string(Key.mode(instance), or: defaults.mode.rawValue)) ?? defaults.mode,
            showsArtwork: store.bool(Key.showsArtwork(instance), or: defaults.showsArtwork),
            showsProgress: store.bool(Key.showsProgress(instance), or: defaults.showsProgress),
            dimsWhenPaused: store.bool(Key.dimsWhenPaused(instance), or: defaults.dimsWhenPaused),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "nowPlaying") {
        SettingsStore.shared.set([
            Key.mode(instance): mode.rawValue,
            Key.showsArtwork(instance): showsArtwork,
            Key.showsProgress(instance): showsProgress,
            Key.dimsWhenPaused(instance): dimsWhenPaused,
            Key.accent(instance): accentHex,
        ])
    }
}
