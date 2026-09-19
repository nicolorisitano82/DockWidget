import AppKit

struct NowPlayingSettings: Equatable {
    var showsArtwork = true
    var showsProgress = true
    var dimsWhenPaused = true
    var accentHex = "#0A84FF"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static let showsArtwork = "nowPlaying.showsArtwork"
        static let showsProgress = "nowPlaying.showsProgress"
        static let dimsWhenPaused = "nowPlaying.dimsWhenPaused"
        static let accent = "nowPlaying.accent"
    }

    static var current: NowPlayingSettings {
        let store = SettingsStore.shared
        let defaults = NowPlayingSettings()
        return NowPlayingSettings(
            showsArtwork: store.bool(Key.showsArtwork, or: defaults.showsArtwork),
            showsProgress: store.bool(Key.showsProgress, or: defaults.showsProgress),
            dimsWhenPaused: store.bool(Key.dimsWhenPaused, or: defaults.dimsWhenPaused),
            accentHex: store.string(Key.accent, or: defaults.accentHex)
        )
    }
}
