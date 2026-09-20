import AppKit

struct ClockSettings: Equatable {
    enum Style: String, CaseIterable {
        case analog, digital, flip, rings, minimal, word

        var label: String {
            switch self {
            case .analog: return T("Analogico", "Analog")
            case .digital: return T("Digitale", "Digital")
            case .flip: return "Flip"
            case .rings: return T("Anelli", "Rings")
            case .minimal: return T("Minimale", "Minimal")
            case .word: return T("A parole", "In words")
            }
        }

        var face: ClockFace {
            switch self {
            case .analog: return AnalogFace()
            case .digital: return DigitalFace()
            case .flip: return FlipFace()
            case .rings: return RingsFace()
            case .minimal: return MinimalFace()
            case .word: return WordFace()
            }
        }
    }

    enum HourFormat: String, CaseIterable {
        case system, h12, h24
        var label: String {
            switch self {
            case .system: return T("Come il sistema", "Follow the system")
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
    /// Empty means the Mac's own zone.
    var timeZoneID: String = ""

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .autoupdatingCurrent }

    var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        return calendar
    }

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemRed }

    enum Key {
        static let style = "clock.style"
        static let hourFormat = "clock.hourFormat"
        static let showsSeconds = "clock.showsSeconds"
        static let showsDate = "clock.showsDate"
        static let accent = "clock.accent"
        static let timeZone = "clock.timeZone"
    }

    static var current: ClockSettings {
        let store = SettingsStore.shared
        let defaults = ClockSettings()
        return ClockSettings(
            style: Style(rawValue: store.string(Key.style, or: defaults.style.rawValue)) ?? defaults.style,
            hourFormat: HourFormat(rawValue: store.string(Key.hourFormat, or: defaults.hourFormat.rawValue)) ?? defaults.hourFormat,
            showsSeconds: store.bool(Key.showsSeconds, or: defaults.showsSeconds),
            showsDate: store.bool(Key.showsDate, or: defaults.showsDate),
            accentHex: store.string(Key.accent, or: defaults.accentHex),
            timeZoneID: store.string(Key.timeZone, or: defaults.timeZoneID)
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

/// A short list of zones, because a picker with six hundred entries is not a
/// picker. "" is the Mac's own zone.
enum ClockZones {
    static let all: [(label: String, identifier: String)] = [
        (T("Fuso del Mac", "The Mac's own zone"), ""),
        ("Roma", "Europe/Rome"),
        ("Londra", "Europe/London"),
        ("Parigi", "Europe/Paris"),
        ("Berlino", "Europe/Berlin"),
        ("Madrid", "Europe/Madrid"),
        ("Atene", "Europe/Athens"),
        ("Mosca", "Europe/Moscow"),
        ("New York", "America/New_York"),
        ("Chicago", "America/Chicago"),
        ("Denver", "America/Denver"),
        ("Los Angeles", "America/Los_Angeles"),
        ("São Paulo", "America/Sao_Paulo"),
        ("Dubai", "Asia/Dubai"),
        ("Mumbai", "Asia/Kolkata"),
        ("Shanghai", "Asia/Shanghai"),
        ("Tokyo", "Asia/Tokyo"),
        ("Singapore", "Asia/Singapore"),
        ("Sydney", "Australia/Sydney"),
        ("Auckland", "Pacific/Auckland"),
        ("UTC", "UTC"),
    ]
}
