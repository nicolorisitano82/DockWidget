import AppKit

/// One line of a song, and when it is sung.
struct LyricLine: Equatable {
    var at: TimeInterval
    var text: String
}

/// Synced lyrics for whatever is playing.
///
/// The words come from LRCLIB, a community database that answers without a key
/// and without an account — which is the only kind of service a project like
/// this one can lean on. One request per track, and a track with nothing to
/// find is remembered as such so it is not asked for twice.
final class LyricsStore {
    static let shared = LyricsStore()

    enum State: Equatable {
        case idle
        case searching
        case missing
        case instrumental
        case lines([LyricLine])
    }

    private(set) var state: State = .idle
    /// Which line is being sung, or nil between them.
    private(set) var index: Int?

    private var key = ""
    private var known: [String: State] = [:]
    private var listeners: [UUID: () -> Void] = [:]
    private var ticker: Timer?

    private init() {}

    @discardableResult
    func addListener(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        start()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func start() {
        guard ticker == nil else { return }
        // Five times a second: enough for a line to land on the beat, and the
        // views are only woken when the line actually changes.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: Following the track

    private func tick() {
        let playing = NowPlayingSource.shared.state
        let current = trackKey(for: playing)
        if current != key {
            key = current
            index = nil
            guard !current.isEmpty else {
                set(.idle)
                return
            }
            if let remembered = known[current] {
                set(remembered)
            } else {
                set(.searching)
                fetch(for: playing, key: current)
            }
            return
        }

        guard case let .lines(lines) = state, let at = playing.progressSeconds() else { return }
        let found = lines.lastIndex { $0.at <= at + 0.15 }
        guard found != index else { return }
        index = found
        listeners.values.forEach { $0() }
    }

    private func trackKey(for playing: NowPlayingState) -> String {
        guard playing.hasTrack else { return "" }
        return [playing.title, playing.artist, playing.album]
            .compactMap { $0 }.joined(separator: "|")
    }

    private func set(_ next: State) {
        guard next != state else { return }
        state = next
        listeners.values.forEach { $0() }
    }

    /// What to put on the line: the words being sung, or dots while the music
    /// plays on without any.
    func current(dots frame: Int) -> String? {
        switch state {
        case .idle, .searching, .missing: return nil
        case .instrumental: return String(repeating: "· ", count: 3).trimmingCharacters(in: .whitespaces)
        case let .lines(lines):
            guard let index, index >= 0, index < lines.count else {
                // Before the first line, and in the gaps, the dots breathe so
                // the widget does not look stuck.
                return String(repeating: "·", count: 1 + frame % 3)
            }
            return lines[index].text
        }
    }

    // MARK: Fetching

    private func fetch(for playing: NowPlayingState, key: String) {
        guard let title = playing.title, !title.isEmpty else { return }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [URLQueryItem(name: "track_name", value: title)]
        if let artist = playing.artist, !artist.isEmpty {
            query.append(URLQueryItem(name: "artist_name", value: artist))
        }
        if let album = playing.album, !album.isEmpty {
            query.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = playing.duration, duration > 1 {
            query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = query
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // LRCLIB asks to be told who is calling, which is only polite.
        request.setValue("Underdock (https://github.com/nicolorisitano82/Underdock)",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let found = Self.parse(data: data, response: response)
            DispatchQueue.main.async {
                guard let self else { return }
                self.known[key] = found
                guard key == self.key else { return }
                self.index = nil
                self.set(found)
            }
        }.resume()
    }

    private static func parse(data: Data?, response: URLResponse?) -> State {
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return .missing }
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .missing }
        if root["instrumental"] as? Bool == true { return .instrumental }
        guard let text = root["syncedLyrics"] as? String, !text.isEmpty else { return .missing }
        let lines = parse(lrc: text)
        return lines.isEmpty ? .missing : .lines(lines)
    }

    /// `[mm:ss.cc] words`, which is all an LRC file is. A line can carry
    /// several stamps for a repeated chorus, so each one becomes its own entry.
    static func parse(lrc: String) -> [LyricLine] {
        var found: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var stamps: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                let parts = inside.components(separatedBy: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    stamps.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            guard !stamps.isEmpty else { continue }
            for stamp in stamps { found.append(LyricLine(at: stamp, text: words)) }
        }
        return found.sorted { $0.at < $1.at }
    }
}
