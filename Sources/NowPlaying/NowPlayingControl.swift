import AppKit

/// Sends a transport command by whichever road is open.
///
/// The first road is the plug-in inside the Dock's process, the only one
/// MediaRemote answers — but it exists only while the widget has a tile in the
/// Dock. Put the widget in the notch alone and there is nobody to carry the
/// command, which is why the buttons did nothing there.
///
/// The second road is the media keys themselves: the same event a keyboard
/// sends, posted to the system, which whatever is playing will obey.
enum NowPlayingControl {
    static func send(_ command: NowPlayingFeed.Command) {
        if hasLiveReader {
            NowPlayingFeed.send(command)
            return
        }
        switch command {
        case .togglePlayPause: press(16)
        case .next: press(17)
        case .previous: press(18)
        case .seek:
            // No key means "go to this second": without the privileged reader
            // the bar can still be scrubbed, just not from here.
            NowPlayingFeed.send(command)
        }
    }

    /// Whether anything has published recently enough to still be listening.
    private static var hasLiveReader: Bool {
        guard let data = try? Data(contentsOf: NowPlayingFeed.stateURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publishedAt = payload["updatedAt"] as? Double else { return false }
        return Date().timeIntervalSince1970 - publishedAt < 30
    }

    /// The system-defined event a media key produces. Needs the permission to
    /// post events, which the agent already has for reading the Dock's layout.
    private static func press(_ key: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))
            let data1 = Int((key << 16) | (isDown ? 0xA00 : 0xB00))
            let event = NSEvent.otherEvent(with: .systemDefined,
                                           location: .zero,
                                           modifierFlags: flags,
                                           timestamp: 0,
                                           windowNumber: 0,
                                           context: nil,
                                           subtype: 8,
                                           data1: data1,
                                           data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
