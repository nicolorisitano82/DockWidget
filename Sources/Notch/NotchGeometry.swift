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

    /// The strip of menu bar on one side of the notch.
    ///
    /// On a Mac without a notch the menu bar is one piece, and the strips are
    /// taken either side of where the panel comes down, so the level readouts
    /// still have somewhere to sit.
    static func auxiliaryArea(on screen: NSScreen, side: NotchSide) -> NSRect? {
        if let area = side == .left ? screen.auxiliaryTopLeftArea : screen.auxiliaryTopRightArea {
            return area
        }
        guard !hasNotch else { return nil }
        let notch = rect(on: screen)
        return side == .left
            ? NSRect(x: screen.frame.minX, y: notch.minY,
                     width: notch.minX - screen.frame.minX, height: notch.height)
            : NSRect(x: notch.maxX, y: notch.minY,
                     width: screen.frame.maxX - notch.maxX, height: notch.height)
    }
}

/// The widget kinds that can go in the notch.
///
/// One list, in the layer both sides can see: the manager offers them and the
/// agent builds them, and two copies would drift apart the first time one of
/// them gained a widget.
enum NotchOffering {
    static let kinds = ["nowplaying", "sensors", "disks", "actions", "note",
                        "applenotes", "shelf", "calendar", "weather"]

    static var instances: [String] { kinds.map(WidgetInstance.notchID(kind:)) }
}

enum NotchSide: String, CaseIterable {
    case left, right
    var label: String { self == .left ? T("Sinistra", "Left") : T("Destra", "Right") }
}

/// What a strip beside the notch shows.
enum NotchLevelKind: String, CaseIterable {
    case none, brightness, volume

    var label: String {
        switch self {
        case .none: return T("Niente", "Nothing")
        case .brightness: return T("Luminosità", "Brightness")
        case .volume: return T("Volume", "Volume")
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle"
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.2.fill"
        }
    }
}

struct NotchSettings: Equatable {
    /// Three at most: the panel drops from a slot the width of a notch, and a
    /// list that runs past the screen would defeat the point of it.
    static let maximumWidgets = 3

    /// How wide the panel opens. Fixed: a notch panel is a shape people
    /// recognise, and a width that moves makes it a different shape each time.
    static let expandedWidth: CGFloat = 400

    var isEnabled = false
    /// Instance identifiers, in the order they are shown.
    var widgets: [String] = ["nowplaying"]
    /// How long the pointer has to stay on the notch before it opens. Opening
    /// the instant the pointer crosses it means opening every time somebody
    /// reaches for the menu bar.
    var openDelay: TimeInterval = 0.25
    /// And how long it waits before closing again, so that crossing a corner
    /// on the way to a button does not shut it.
    var closeDelay: TimeInterval = 0.35
    /// What sits in the strip left of the notch, and right of it.
    var leftLevel: NotchLevelKind = .none
    var rightLevel: NotchLevelKind = .none
    /// How much one notch of the scroll wheel, or one arrow key, moves a level.
    /// A sixteenth is what the keyboard's own brightness and volume keys do.
    var levelStep: Double = 1.0 / 16.0

    func level(on side: NotchSide) -> NotchLevelKind {
        side == .left ? leftLevel : rightLevel
    }

    enum Key {
        static let enabled = "notch.enabled"
        static let widgets = "notch.widgets"
        static let openDelay = "notch.openDelay"
        static let closeDelay = "notch.closeDelay"
        static let leftLevel = "notch.leftLevel"
        static let rightLevel = "notch.rightLevel"
        static let levelStep = "notch.levelStep"
    }

    static var current: NotchSettings {
        let store = SettingsStore.shared
        let defaults = NotchSettings()
        let stored = store.strings(Key.widgets) ?? []
        return NotchSettings(
            isEnabled: store.bool(Key.enabled, or: defaults.isEnabled),
            widgets: stored.isEmpty ? defaults.widgets : Array(stored.prefix(maximumWidgets)),
            openDelay: store.double(Key.openDelay, or: defaults.openDelay),
            closeDelay: store.double(Key.closeDelay, or: defaults.closeDelay),
            leftLevel: NotchLevelKind(rawValue: store.string(Key.leftLevel,
                                                             or: defaults.leftLevel.rawValue))
                ?? defaults.leftLevel,
            rightLevel: NotchLevelKind(rawValue: store.string(Key.rightLevel,
                                                              or: defaults.rightLevel.rawValue))
                ?? defaults.rightLevel,
            levelStep: store.double(Key.levelStep, or: defaults.levelStep)
        )
    }

    func save() {
        SettingsStore.shared.set([
            Key.enabled: isEnabled,
            Key.widgets: widgets,
            Key.openDelay: openDelay,
            Key.closeDelay: closeDelay,
            Key.leftLevel: leftLevel.rawValue,
            Key.rightLevel: rightLevel.rawValue,
            Key.levelStep: levelStep,
        ])
    }
}
