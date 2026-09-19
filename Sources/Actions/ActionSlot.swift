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
        case .none: return "Nessuna azione"
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
        case .lockScreen: return "Blocca lo schermo"
        case .sleep: return "Sospendi"
        case .screenSaver: return "Salvaschermo"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Mostra la scrivania"
        case .emptyTrash: return "Svuota il cestino"
        case .playPause: return "Play / Pausa"
        case .screenshot: return "Screenshot di un'area"
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
    static let slotCount = 4
    static let key = "actions.slots"

    var slots: [ActionSlot]

    static var current: ActionsSettings {
        let raw = SettingsStore.shared.string(key, or: "")
        guard let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([ActionSlot].self, from: data),
              !stored.isEmpty else {
            return ActionsSettings(slots: defaults)
        }
        var slots = stored
        while slots.count < slotCount { slots.append(.empty) }
        return ActionsSettings(slots: Array(slots.prefix(slotCount)))
    }

    func save() {
        guard let data = try? JSONEncoder().encode(slots),
              let text = String(data: data, encoding: .utf8) else { return }
        SettingsStore.shared.set(text, for: Self.key)
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
