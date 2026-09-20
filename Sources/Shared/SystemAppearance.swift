import AppKit

extension Notification.Name {
    /// Posted in-process whenever the user's light/dark setting changes.
    static let tileAppearanceChanged = Notification.Name("dev.nicolo.underdock.appearanceChanged")
}

/// Light/dark read straight from the global preferences domain.
///
/// The plug-in is loaded into the Dock's plug-in host (`com.apple.dock.external.extra`),
/// a process whose `NSApp` appearance is not ours to configure, so we never ask AppKit
/// what the user's theme is — we read it and watch for the system's change notification.
final class SystemAppearance {
    static let shared = SystemAppearance()

    /// Set only by the tools that render the widgets for the site or for a
    /// check: everything else follows the Mac.
    var override: Bool? {
        didSet { NotificationCenter.default.post(name: .tileAppearanceChanged, object: nil) }
    }

    private var systemIsDark: Bool
    var isDark: Bool { override ?? systemIsDark }

    private init() {
        systemIsDark = Self.read()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let updated = Self.read()
            guard updated != self.systemIsDark else { return }
            self.systemIsDark = updated
            NotificationCenter.default.post(name: .tileAppearanceChanged, object: nil)
        }
    }

    private static func read() -> Bool {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["AppleInterfaceStyle"] as? String == "Dark"
    }

    var nsAppearance: NSAppearance {
        NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance()
    }
}
