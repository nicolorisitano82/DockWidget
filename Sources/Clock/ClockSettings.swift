import AppKit

struct ClockSettings: Equatable {
    enum Style: String, CaseIterable {
        case analog, digital
        var label: String { self == .analog ? "Analogico" : "Digitale" }
    }

    enum HourFormat: String, CaseIterable {
        case system, h12, h24
        var label: String {
            switch self {
            case .system: return "Come il sistema"
            case .h12: return "12 ore"
            case .h24: return "24 ore"
            }
        }
    }

    var style: Style = .analog
    var hourFormat: HourFormat = .system
    var showsSeconds: Bool = true
    var showsDate: Bool = true
    var accentHex: String = "#FF453A"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemRed }

    enum Key {
        static let style = "clock.style"
        static let hourFormat = "clock.hourFormat"
        static let showsSeconds = "clock.showsSeconds"
        static let showsDate = "clock.showsDate"
        static let accent = "clock.accent"
    }

    static var current: ClockSettings {
        let store = SettingsStore.shared
        let defaults = ClockSettings()
        return ClockSettings(
            style: Style(rawValue: store.string(Key.style, or: defaults.style.rawValue)) ?? defaults.style,
            hourFormat: HourFormat(rawValue: store.string(Key.hourFormat, or: defaults.hourFormat.rawValue)) ?? defaults.hourFormat,
            showsSeconds: store.bool(Key.showsSeconds, or: defaults.showsSeconds),
            showsDate: store.bool(Key.showsDate, or: defaults.showsDate),
            accentHex: store.string(Key.accent, or: defaults.accentHex)
        )
    }

    /// The time format the digital face and the "copy time" menu item share.
    func timeFormat() -> String {
        switch hourFormat {
        case .system:
            let template = showsSeconds ? "jms" : "jm"
            return DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: .autoupdatingCurrent) ?? "HH:mm"
        case .h12:
            return showsSeconds ? "h:mm:ss a" : "h:mm a"
        case .h24:
            return showsSeconds ? "HH:mm:ss" : "HH:mm"
        }
    }
}
