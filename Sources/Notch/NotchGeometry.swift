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
    /// How much room the panel has, counted in rows. A widget takes one, or
    /// two when it has something worth the extra height.
    static let slots = 4
    /// Which is also the most widgets there can be, all of them taking one.
    static let maximumWidgets = slots

    static func spanKey(_ instance: String) -> String { "\(instance).notchSpan" }

    /// How many rows this copy takes: one, or two where that is allowed.
    static func span(of instance: String) -> Int {
        guard canSpanTwo(instance) else { return 1 }
        return min(max(Int(SettingsStore.shared.double(spanKey(instance), or: 1)), 1), 2)
    }

    static func setSpan(_ span: Int, for instance: String) {
        SettingsStore.shared.set(Double(min(max(span, 1), 2)), for: spanKey(instance))
    }

    /// Whether two rows would say more than one. A widget that has nothing to
    /// put in the extra height is not offered it.
    static func canSpanTwo(_ instance: String) -> Bool {
        ["nowplaying", "weather", "calendar", "sensors", "shelf"]
            .contains(WidgetInstance.kind(of: instance))
    }

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
    /// A thin line of actions under the last widget. The cells themselves are
    /// an actions widget like any other, kept under this name.
    static let actionBarInstance = "notchbar"
    var showsActionBar = true

    /// What sits in the strip left of the notch, and right of it.
    var leftLevel: NotchLevelKind = .none
    var rightLevel: NotchLevelKind = .none
    /// How much one notch of the scroll wheel, or one arrow key, moves a level.
    /// A sixteenth is what the keyboard's own brightness and volume keys do.
    var levelStep: Double = 1.0 / 16.0

    func level(on side: NotchSide) -> NotchLevelKind {
        side == .left ? leftLevel : rightLevel
    }

    /// The rows that fit: taken in order until the caselle run out, so a
    /// widget grown to two rows pushes the last one off rather than
    /// overflowing the panel.
    var fittedWidgets: [String] {
        var spent = 0
        var kept: [String] = []
        for instance in widgets {
            let span = NotchSettings.span(of: instance)
            guard spent + span <= NotchSettings.slots else { continue }
            spent += span
            kept.append(instance)
        }
        return kept
    }

    enum Key {
        static let enabled = "notch.enabled"
        static let widgets = "notch.widgets"
        static let openDelay = "notch.openDelay"
        static let closeDelay = "notch.closeDelay"
        static let leftLevel = "notch.leftLevel"
        static let rightLevel = "notch.rightLevel"
        static let levelStep = "notch.levelStep"
        static let actionBar = "notch.actionBar"
    }

    static var current: NotchSettings {
        let store = SettingsStore.shared
        let defaults = NotchSettings()
        let stored = store.strings(Key.widgets) ?? []
        return NotchSettings(
            isEnabled: store.bool(Key.enabled, or: defaults.isEnabled),
            widgets: stored.isEmpty ? defaults.widgets : Array(stored.prefix(slots)),
            openDelay: store.double(Key.openDelay, or: defaults.openDelay),
            closeDelay: store.double(Key.closeDelay, or: defaults.closeDelay),
            showsActionBar: store.bool(Key.actionBar, or: defaults.showsActionBar),
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
            Key.actionBar: showsActionBar,
        ])
    }
}
