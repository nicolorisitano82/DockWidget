import AppKit

/// What one cell of the actions widget does when clicked.
enum ActionKind: Codable, Equatable {
    case none
    case app(path: String)
    case open(target: String)
    case shortcut(name: String)
    case system(SystemAction)

    var summary: String {
        switch self {
        case .none: return T("Nessuna azione", "No action")
        case .app(let path): return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case .open(let target): return target
        case .shortcut(let name): return name
        case .system(let action): return action.label
        }
    }
}

enum SystemAction: String, Codable, CaseIterable {
    case lockScreen, sleep, screenSaver, missionControl, showDesktop
    case emptyTrash, playPause, screenshot

    var label: String {
        switch self {
        case .lockScreen: return T("Blocca lo schermo", "Lock the screen")
        case .sleep: return T("Sospendi", "Sleep")
        case .screenSaver: return T("Salvaschermo", "Screen saver")
        case .missionControl: return T("Mission Control", "Mission Control")
        case .showDesktop: return T("Mostra la scrivania", "Show the desktop")
        case .emptyTrash: return T("Svuota il cestino", "Empty the Trash")
        case .playPause: return T("Play / Pausa", "Play / Pause")
        case .screenshot: return T("Screenshot di un'area", "Screenshot of an area")
        }
    }
}

struct ActionSlot: Codable, Equatable {
    var symbol: String
    var iconHex: String
    var backgroundHex: String
    var kind: ActionKind

    var icon: NSColor { NSColor(hexString: iconHex) ?? .white }
    var background: NSColor { NSColor(hexString: backgroundHex) ?? .systemBlue }
    var isEmpty: Bool { kind == .none }

    static let empty = ActionSlot(symbol: "square.dashed", iconHex: "#98989D",
                                  backgroundHex: "#2C2C2E", kind: .none)
}

struct ActionsSettings: Equatable {
    /// How many cells a copy shows. Four is what fits beside the Dock's icons;
    /// stacked in the notch a row is much wider than that, so the number is the
    /// widget's own rather than the same everywhere.
    static let defaultSlots = 4
    static let minimumSlots = 2
    static let maximumSlots = 10

    static func key(_ instance: String) -> String { "\(instance).slots" }
    static func countKey(_ instance: String) -> String { "\(instance).cells" }

    var slots: [ActionSlot]

    var count: Int { slots.count }

    static var current: ActionsSettings { current("actions") }

    static func current(_ instance: String) -> ActionsSettings {
        let wanted = min(max(Int(SettingsStore.shared.double(countKey(instance),
                                                             or: Double(defaultSlots))),
                             minimumSlots), maximumSlots)
        let raw = SettingsStore.shared.string(key(instance), or: "")
        var slots: [ActionSlot]
        if let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode([ActionSlot].self, from: data),
           !stored.isEmpty {
            slots = stored
        } else {
            slots = defaults
        }
        while slots.count < wanted { slots.append(.empty) }
        return ActionsSettings(slots: Array(slots.prefix(wanted)))
    }

    func save(_ instance: String = "actions") {
        guard let data = try? JSONEncoder().encode(slots),
              let text = String(data: data, encoding: .utf8) else { return }
        SettingsStore.shared.set([
            Self.key(instance): text,
            Self.countKey(instance): Double(slots.count),
        ])
    }

    /// Something useful on first run, so the widget is not four empty holes.
    static let defaults: [ActionSlot] = [
        ActionSlot(symbol: "lock.fill", iconHex: "#FFFFFF", backgroundHex: "#0A84FF",
                   kind: .system(.lockScreen)),
        ActionSlot(symbol: "playpause.fill", iconHex: "#FFFFFF", backgroundHex: "#32D74B",
                   kind: .system(.playPause)),
        ActionSlot(symbol: "macwindow.on.rectangle", iconHex: "#FFFFFF", backgroundHex: "#FF9F0A",
                   kind: .system(.missionControl)),
        ActionSlot(symbol: "camera.viewfinder", iconHex: "#FFFFFF", backgroundHex: "#BF5AF2",
                   kind: .system(.screenshot)),
    ]
}

/// A short, curated set of SF Symbols: the whole catalogue is six thousand
/// entries, and a picker is only useful if you can see the end of it.
enum ActionSymbols {
    static let all: [String] = [
        "lock.fill", "moon.fill", "display", "macwindow.on.rectangle", "desktopcomputer",
        "playpause.fill", "play.fill", "forward.fill", "backward.fill", "speaker.wave.2.fill",
        "camera.viewfinder", "photo", "trash.fill", "folder.fill", "doc.fill",
        "envelope.fill", "message.fill", "phone.fill", "video.fill", "calendar",
        "bell.fill", "clock.fill", "alarm.fill", "timer", "stopwatch.fill",
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles",
        "gearshape.fill", "wrench.and.screwdriver.fill", "hammer.fill", "terminal.fill", "chevron.left.forwardslash.chevron.right",
        "globe", "safari.fill", "link", "magnifyingglass", "bookmark.fill",
        "music.note", "headphones", "mic.fill", "tv.fill", "gamecontroller.fill",
        "cart.fill", "creditcard.fill", "banknote", "chart.bar.fill", "list.bullet",
        "checkmark.circle.fill", "xmark.circle.fill", "plus.circle.fill", "arrow.clockwise", "arrow.up.right.square.fill",
        "wifi", "antenna.radiowaves.left.and.right", "airplane", "car.fill", "figure.walk",
        "house.fill", "building.2.fill", "map.fill", "location.fill", "sun.max.fill",
        "cloud.fill", "umbrella.fill", "leaf.fill", "pawprint.fill", "cup.and.saucer.fill",
    ]
}
