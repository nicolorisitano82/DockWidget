import AppKit

struct NowPlayingState {
    enum Origin: String {
        /// MediaRemote answered — full metadata, artwork and transport control.
        case mediaRemote
        /// Music/Spotify broadcasts — title and artist only, no artwork, no control.
        case broadcast
        case none
    }

    var title: String?
    var artist: String?
    var album: String?
    var isPlaying = false
    var artwork: NSImage?
    var playerBundleID: String?
    var origin: Origin = .none

    /// Playback position as reported, and when it was reported, so the tile can
    /// project it forward instead of redrawing a frozen bar.
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    var elapsedSampledAt = Date()

    var hasTrack: Bool { !(title ?? "").isEmpty }

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

    /// Everything the tile draws — used to skip redraws that would change nothing.
    func renderToken(at date: Date = Date()) -> String {
        let bar = Int((progress(at: date) ?? 0) * 200)
        return [title ?? "", artist ?? "", isPlaying ? "1" : "0", playerBundleID ?? "", String(bar)]
            .joined(separator: "|")
    }
}
