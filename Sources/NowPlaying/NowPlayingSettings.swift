import AppKit

struct NowPlayingSettings: Equatable {
    enum Mode: String, CaseIterable {
        /// A square Dock tile drawn by the plug-in.
        case tile
        /// A wide interactive bar drawn by the agent over spacer tiles.
        case bar

        var label: String { self == .tile ? "Tile" : "Barra" }
    }

    var mode: Mode = .tile
    var showsArtwork = true
    var showsProgress = true
    var dimsWhenPaused = true
    var accentHex = "#0A84FF"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static let mode = "nowPlaying.mode"
        static let showsArtwork = "nowPlaying.showsArtwork"
        static let showsProgress = "nowPlaying.showsProgress"
        static let dimsWhenPaused = "nowPlaying.dimsWhenPaused"
        static let accent = "nowPlaying.accent"
    }

    static var current: NowPlayingSettings {
        let store = SettingsStore.shared
        let defaults = NowPlayingSettings()
        return NowPlayingSettings(
            mode: Mode(rawValue: store.string(Key.mode, or: defaults.mode.rawValue)) ?? defaults.mode,
            showsArtwork: store.bool(Key.showsArtwork, or: defaults.showsArtwork),
            showsProgress: store.bool(Key.showsProgress, or: defaults.showsProgress),
            dimsWhenPaused: store.bool(Key.dimsWhenPaused, or: defaults.dimsWhenPaused),
            accentHex: store.string(Key.accent, or: defaults.accentHex)
        )
    }
}
