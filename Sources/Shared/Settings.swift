import AppKit

enum SharedDefaults {
    /// A plain (non-sandboxed) preferences domain both the host app and the
    /// plug-in can reach: ~/Library/Preferences/dev.nicolo.underdock.plist
    static let suiteName = "dev.nicolo.underdock"
    /// What the domain was called under the names the app had before, newest
    /// first. The app was Dock Widgets, then WidgetPro, then Underdock.
    static let legacySuiteNames = ["dev.nicolo.widgetpro", "dev.nicolo.dockwidgets"]
    /// Broadcast by the host after a write so the plug-in can re-read immediately.
    static let changedNotification = Notification.Name("dev.nicolo.underdock.settingsChanged")
}

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: SharedDefaults.suiteName) ?? .standard
        adoptLegacyDomain()
    }

    /// Carries across what was configured under the names the app had before.
    ///
    /// The preferences domain is named after the app, and the app has been
    /// renamed twice. A rename is not a reason for every widget to forget how
    /// it was set up — and a Mac that skipped a version has to come across from
    /// whichever domain it actually has, so they are all tried, newest first.
    ///
    /// Every process that reads settings runs this, and that is fine: the flag
    /// is written into the shared domain, so the first one through does the
    /// work and the rest find it done.
    private func adoptLegacyDomain() {
        let flag = "migrated.into.underdock"
        guard defaults.object(forKey: flag) == nil else { return }
        defaults.set(true, forKey: flag)
        for name in SharedDefaults.legacySuiteNames {
            let stored = UserDefaults(suiteName: name)?.persistentDomain(forName: name) ?? [:]
            guard !stored.isEmpty else { continue }
            for (key, value) in stored where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.synchronize()
            Diagnostics.write("impostazioni adottate dal dominio \(name): \(stored.count) chiavi")
            return
        }
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

    /// Moves settings written under an old key prefix to a new one.
    ///
    /// The now-playing widget was "nowPlaying" in its settings and "nowplaying"
    /// in its bundle identifier; once the identifier became the name of the
    /// instance the two had to agree, and what was already configured had to
    /// come along.
    func migrate(prefix old: String, to new: String) {
        let values = defaults.dictionaryRepresentation()
        var moved = false
        for (key, value) in values where key.hasPrefix(old) {
            let replacement = new + key.dropFirst(old.count)
            guard values[replacement] == nil else { continue }
            defaults.set(value, forKey: replacement)
            defaults.removeObject(forKey: key)
            moved = true
        }
        guard moved else { return }
        defaults.synchronize()
    }

    /// Forgets everything a removed copy of a widget had configured.
    func removeAll(withPrefix prefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            SharedDefaults.changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
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
