import AppKit

enum SharedDefaults {
    /// A plain (non-sandboxed) preferences domain both the host app and the
    /// plug-in can reach: ~/Library/Preferences/dev.nicolo.dockwidgets.plist
    static let suiteName = "dev.nicolo.dockwidgets"
    /// Broadcast by the host after a write so the plug-in can re-read immediately.
    static let changedNotification = Notification.Name("dev.nicolo.dockwidgets.settingsChanged")
}

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: SharedDefaults.suiteName) ?? .standard
    }

    func refresh() {
        defaults.synchronize()
    }

    func bool(_ key: String, or fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    func string(_ key: String, or fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    func strings(_ key: String) -> [String]? {
        defaults.stringArray(forKey: key)
    }

    func double(_ key: String, or fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    /// Writes and tells every other process in the session to re-read.
    func set(_ value: Any?, for key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            SharedDefaults.changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// Writes a batch and broadcasts once, so a settings pane does not fire a
    /// notification per control.
    func set(_ values: [String: Any?]) {
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            SharedDefaults.changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// Calls `handler` on the main queue whenever another process changes a setting.
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: SharedDefaults.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
            handler()
        }
    }
}

extension NSColor {
    /// "#RRGGBB" round-tripping, so an accent colour survives in a plist.
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#0A84FF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
