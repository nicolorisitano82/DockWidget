import AppKit

/// Thin wrapper over the private MediaRemote framework.
///
/// Since macOS 15.4 the now-playing registry only answers callers the system
/// trusts, so an ordinary app gets an empty dictionary back. Inside the Dock's
/// plug-in host the caller is an Apple-signed process, which is why this is
/// worth trying at all — but it is probed, never assumed: `NowPlayingSource`
/// falls back to player broadcasts when nothing comes back.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, stop = 3, next = 4, previous = 5
    }

    enum InfoKey {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let artworkIdentifier = "kMRMediaRemoteNowPlayingInfoArtworkIdentifier"
        static let elapsed = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
    }

    static let infoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetIsPlayingFn?
    private let getPID: GetPIDFn?
    private let register: RegisterFn?
    private let sendCommandFn: SendCommandFn?
    private let setElapsedFn: SetElapsedFn?

    private init() {
        let library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        handle = library
        getInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
        getPID = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: GetPIDFn.self)
        register = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        sendCommandFn = symbol("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        setElapsedFn = symbol("MRMediaRemoteSetElapsedTime", as: SetElapsedFn.self)
    }

    /// The framework loaded and the symbols are there. It says nothing about
    /// whether this process is allowed to read the registry.
    var isLinked: Bool { getInfo != nil }

    var canSendCommands: Bool { sendCommandFn != nil }

    func registerForNotifications() {
        register?(.main)
    }

    /// Scrubs the current track. Silently does nothing where the symbol is gone.
    func setElapsedTime(_ seconds: TimeInterval) {
        setElapsedFn?(seconds)
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }

    /// Reads the registry. `nil` means "nothing came back" — either nothing is
    /// playing or this process is not trusted; the caller cannot tell them apart.
    func readNowPlaying(completion: @escaping (NowPlayingState?) -> Void) {
        guard let getInfo else {
            completion(nil)
            return
        }
        getInfo(.main) { info in
            Diagnostics.once("mediaremote-answer",
                             "MediaRemote ha restituito \(info.count) chiavi: \(info.keys.sorted().prefix(8))")
            guard !info.isEmpty else {
                completion(nil)
                return
            }
            var state = NowPlayingState()
            state.origin = .mediaRemote
            state.title = info[InfoKey.title] as? String
            state.artist = info[InfoKey.artist] as? String
            state.album = info[InfoKey.album] as? String
            state.duration = (info[InfoKey.duration] as? NSNumber)?.doubleValue
            state.isPlaying = ((info[InfoKey.playbackRate] as? NSNumber)?.doubleValue ?? 0) > 0

            if let elapsed = (info[InfoKey.elapsed] as? NSNumber)?.doubleValue {
                // The registry reports a position plus the moment it was sampled;
                // keeping both lets the tile animate without polling.
                state.elapsed = elapsed
                state.elapsedSampledAt = (info[InfoKey.timestamp] as? Date) ?? Date()
            }
            if let data = info[InfoKey.artworkData] as? Data {
                state.artwork = NSImage(data: data)
                state.artworkData = data
                let identifier = info[InfoKey.artworkIdentifier]
                state.artworkIdentifier = (identifier as? String)
                    ?? (identifier as? NSNumber)?.stringValue
            }
            self.resolvePlayerBundleID { bundleID in
                state.playerBundleID = bundleID
                completion(state)
            }
        }
    }

    func readIsPlaying(completion: @escaping (Bool) -> Void) {
        guard let getIsPlaying else {
            completion(false)
            return
        }
        getIsPlaying(.main) { completion($0) }
    }

    private func resolvePlayerBundleID(completion: @escaping (String?) -> Void) {
        guard let getPID else {
            completion(nil)
            return
        }
        getPID(.main) { pid in
            let app = NSRunningApplication(processIdentifier: pid)
            completion(app?.bundleIdentifier)
        }
    }
}
