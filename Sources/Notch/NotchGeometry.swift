import AppKit

/// Where the notch is, and what to do on a Mac that has none.
enum NotchGeometry {
    /// The screen that has a notch, or the one with the menu bar.
    static var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static var hasNotch: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    /// The notch itself, in Cocoa screen coordinates.
    ///
    /// The two auxiliary areas are the usable strips either side of it, so what
    /// is left between them is the notch. Without one, the same shape is taken
    /// at the top centre of the screen: the panel still has somewhere to come
    /// from, it just has nothing to hide behind.
    static func rect(on screen: NSScreen) -> NSRect {
        let height = max(screen.safeAreaInsets.top, 32)
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else {
            let width: CGFloat = 180
            return NSRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.maxY - height,
                          width: width, height: height)
        }
        return NSRect(x: left.maxX, y: screen.frame.maxY - height,
                      width: right.minX - left.maxX, height: height)
    }
}

struct NotchSettings: Equatable {
    /// Three at most: the panel drops from a slot the width of a notch, and a
    /// list that runs past the screen would defeat the point of it.
    static let maximumWidgets = 3

    var isEnabled = false
    /// Instance identifiers, in the order they are shown.
    var widgets: [String] = ["nowplaying"]
    var expandedWidth: CGFloat = 460

    enum Key {
        static let enabled = "notch.enabled"
        static let widgets = "notch.widgets"
        static let width = "notch.width"
    }

    static var current: NotchSettings {
        let store = SettingsStore.shared
        let defaults = NotchSettings()
        let stored = store.strings(Key.widgets) ?? []
        return NotchSettings(
            isEnabled: store.bool(Key.enabled, or: defaults.isEnabled),
            widgets: stored.isEmpty ? defaults.widgets : Array(stored.prefix(maximumWidgets)),
            expandedWidth: CGFloat(store.double(Key.width, or: Double(defaults.expandedWidth)))
        )
    }

    func save() {
        SettingsStore.shared.set([
            Key.enabled: isEnabled,
            Key.widgets: widgets,
            Key.width: Double(expandedWidth),
        ])
    }
}
