import AppKit

/// A release of Underdock, as its own repository describes it.
struct Release {
    /// The version without the "v" the tag carries: "1.1".
    var version: String
    var title: String
    /// The notes, as Markdown.
    var notes: String
    var pageURL: URL?
    var diskImageURL: URL?
    /// How big it is, so the question can say so before the answer costs.
    var size: Int64
}

/// Looking for a newer Underdock, and fetching it when asked.
///
/// Four questions in this order: is there one, shall I fetch it, here it is —
/// shall I open it, and then the application gets out of the way. Nothing is
/// installed behind anybody's back: the disk image lands in Downloads like any
/// other download, and dragging the application across is still done by hand.
enum Updates {
    static let repository = "nicolorisitano82/Underdock"

    enum Key {
        static let automatic = "updates.automatic"
        static let lastCheck = "updates.lastCheck"
    }

    /// Asks the repository what the latest release is. The completion runs on
    /// the main queue.
    static func latest(completion: @escaping (Release?, String?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else {
            completion(nil, T("Indirizzo non valido.", "Bad address."))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Underdock", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(nil, error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion(nil, T("GitHub ha risposto \(http.statusCode).",
                                      "GitHub answered \(http.statusCode)."))
                    return
                }
                guard let data, let release = release(from: data) else {
                    completion(nil, T("Risposta illeggibile.", "Unreadable answer."))
                    return
                }
                completion(release, nil)
            }
        }.resume()
    }

    /// The release GitHub's answer describes, or nil when it describes none.
    static func release(from json: Data) -> Release? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = root["tag_name"] as? String else { return nil }
        let assets = root["assets"] as? [[String: Any]] ?? []
        // The disk image, by extension rather than by name: the name carries
        // the version in some releases and not in others.
        let image = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        return Release(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            title: (root["name"] as? String) ?? tag,
            notes: (root["body"] as? String) ?? "",
            pageURL: (root["html_url"] as? String).flatMap(URL.init(string:)),
            diskImageURL: (image?["browser_download_url"] as? String).flatMap(URL.init(string:)),
            size: Int64((image?["size"] as? Int) ?? 0))
    }

    /// Which of two versions is the later one. Numbers are compared as numbers,
    /// so 1.10 comes after 1.9 rather than before it.
    static func compare(_ one: String, _ other: String) -> ComparisonResult {
        let left = one.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let right = other.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func isNewer(_ release: Release, than running: String) -> Bool {
        compare(release.version, running) == .orderedDescending
    }

    /// A day between one look and the next.
    static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) > 24 * 60 * 60
    }

    /// Whether an address is one of ours to download from.
    ///
    /// The list of releases comes from GitHub over HTTPS, and so must the file
    /// it points at: a feed that has been tampered with should not be able to
    /// send the application off to fetch something from somewhere else.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }

    static var runningVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Where a download goes, and under what name when that one is taken.
    static func downloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func freeFile(in folder: URL, named name: String) -> URL {
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        var attempt = 2
        while manager.fileExists(atPath: candidate.path), attempt < 100 {
            candidate = folder.appendingPathComponent("\(base) \(attempt).\(suffix)")
            attempt += 1
        }
        return candidate
    }
}
