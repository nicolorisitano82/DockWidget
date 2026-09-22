import AppKit

/// Cover art for the players that broadcast what they are playing.
///
/// Music and Spotify say the title and the artist in their notifications and
/// nothing about the artwork, and MediaRemote — which does have it — answers
/// only inside the Dock's plug-in host. So when the Now Playing widget lives
/// in the notch alone, with no tile in the Dock to load that plug-in, the
/// cover has to be asked for directly: Music hands over the bytes, Spotify
/// hands over an address.
///
/// Both are asked through AppleScript, which means the first time round macOS
/// asks the user whether Underdock may talk to that app. A refusal costs the
/// cover and nothing else.
enum BroadcastArtwork {
    private static var cachedKey = ""
    private static var cachedImage: NSImage?
    private static var inFlight = ""

    /// The cover for what is playing, if it has already been fetched.
    static func cached(for key: String) -> NSImage? {
        key == cachedKey ? cachedImage : nil
    }

    /// Asks the player for its cover, once per track.
    ///
    /// The handler runs on the main queue, and only when there is something
    /// new to show.
    static func fetch(bundleID: String, key: String,
                      completion: @escaping (NSImage) -> Void) {
        guard !key.isEmpty, key != cachedKey, key != inFlight else { return }
        // Never wake a player that is not running just to ask it a question.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        else { return }
        inFlight = key

        switch bundleID {
        case "com.apple.Music":
            fromMusic(key: key, completion: completion)
        case "com.spotify.client":
            fromSpotify(key: key, completion: completion)
        default:
            inFlight = ""
        }
    }

    private static func keep(_ image: NSImage, for key: String,
                             _ completion: @escaping (NSImage) -> Void) {
        cachedKey = key
        cachedImage = image
        inFlight = ""
        completion(image)
    }

    private static func give(up key: String) {
        if inFlight == key { inFlight = "" }
    }

    // MARK: Music

    private static func fromMusic(key: String, completion: @escaping (NSImage) -> Void) {
        // AppleScript is not thread-safe, so it stays on the main queue; the
        // ask is a few milliseconds and happens once per track.
        DispatchQueue.main.async {
            let source = """
            tell application "Music"
                if player state is stopped then return missing value
                try
                    return raw data of artwork 1 of current track
                on error
                    return missing value
                end try
            end tell
            """
            var error: NSDictionary?
            guard let result = NSAppleScript(source: source)?
                    .executeAndReturnError(&error) else {
                if let error {
                    Diagnostics.once("artwork-music-\(error["NSAppleScriptErrorNumber"] ?? "?")",
                                     "copertina da Musica: \(error["NSAppleScriptErrorMessage"] ?? error)")
                }
                give(up: key)
                return
            }
            guard let data = result.data as Data?, !data.isEmpty,
                  let image = NSImage(data: data) else {
                give(up: key)
                return
            }
            keep(image, for: key, completion)
        }
    }

    // MARK: Spotify

    private static func fromSpotify(key: String, completion: @escaping (NSImage) -> Void) {
        DispatchQueue.main.async {
            let source = """
            tell application "Spotify"
                if player state is stopped then return ""
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                Diagnostics.once("artwork-spotify-\(error["NSAppleScriptErrorNumber"] ?? "?")",
                                 "copertina da Spotify: \(error["NSAppleScriptErrorMessage"] ?? error)")
            }
            guard let address = result?.stringValue, let url = URL(string: address),
                  url.scheme?.hasPrefix("http") == true else {
                give(up: key)
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            URLSession.shared.dataTask(with: request) { data, _, _ in
                DispatchQueue.main.async {
                    guard let data, let image = NSImage(data: data) else {
                        give(up: key)
                        return
                    }
                    keep(image, for: key, completion)
                }
            }.resume()
        }
    }
}
