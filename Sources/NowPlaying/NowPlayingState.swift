import AppKit

struct NowPlayingState {
    enum Origin: String {
        /// MediaRemote answered — full metadata, artwork and transport control.
        case mediaRemote
        /// Music/Spotify broadcasts — title and artist only, no artwork, no control.
        case broadcast
        /// Relayed by the Dock plug-in, which is the only process MediaRemote answers.
        case published
        case none
    }

    var title: String?
    var artist: String?
    var album: String?
    var isPlaying = false
    var artwork: NSImage?
    /// The bytes as the player published them, kept so they can be relayed
    /// without a re-encode.
    var artworkData: Data?
    var artworkIdentifier: String?
    var playerBundleID: String?
    var origin: Origin = .none

    /// Playback position as reported, and when it was reported, so the tile can
    /// project it forward instead of redrawing a frozen bar.
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    var elapsedSampledAt = Date()

    var hasTrack: Bool { !(title ?? "").isEmpty }

    /// Set when the cover was fetched from the player itself, which is how a
    /// broadcast — who otherwise only knows the title — comes to have one.
    var fetchedCoverArt = false

    /// True when `artwork` is real cover art rather than a stand-in player icon.
    var hasCoverArt: Bool {
        fetchedCoverArt || origin == .mediaRemote || origin == .published
    }

    /// What identifies the track for the purpose of fetching its cover once.
    var artworkKey: String {
        [playerBundleID, title, album].compactMap { $0 }.joined(separator: "|")
    }

    var subtitle: String? {
        let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    func progress(at date: Date = Date()) -> Double? {
        guard let duration, duration > 1, var elapsed else { return nil }
        if isPlaying {
            elapsed += date.timeIntervalSince(elapsedSampledAt)
        }
        return min(max(elapsed / duration, 0), 1)
    }

    /// Where the track is, in seconds, projected forward from when it was
    /// last reported — which is what the lyrics have to line up with.
    func progressSeconds(at date: Date = Date()) -> TimeInterval? {
        guard var elapsed else { return nil }
        if isPlaying { elapsed += date.timeIntervalSince(elapsedSampledAt) }
        return max(elapsed, 0)
    }

    /// Everything the tile draws — used to skip redraws that would change nothing.
    func renderToken(at date: Date = Date()) -> String {
        let bar = Int((progress(at: date) ?? 0) * 200)
        return [title ?? "", artist ?? "", isPlaying ? "1" : "0", playerBundleID ?? "", String(bar)]
            .joined(separator: "|")
    }
}
