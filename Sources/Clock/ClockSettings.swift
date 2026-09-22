import AppKit

struct ClockSettings: Equatable {
    enum Style: String, CaseIterable {
        case analog, digital, flip, rings, minimal, word, binary, day, matrix

        var label: String {
            switch self {
            case .analog: return T("Analogico", "Analog")
            case .digital: return T("Digitale", "Digital")
            case .flip: return "Flip"
            case .rings: return T("Anelli", "Rings")
            case .minimal: return T("Minimale", "Minimal")
            case .word: return T("A parole", "In words")
            case .binary: return T("Binario", "Binary")
            case .day: return T("Giornata", "The day")
            case .matrix: return T("Tabellone", "Board")
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
            case .binary: return BinaryFace()
            case .day: return DayFace()
            case .matrix: return MatrixFace()
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
        static func style(_ instance: String) -> String { "\(instance).style" }
        static func hourFormat(_ instance: String) -> String { "\(instance).hourFormat" }
        static func showsSeconds(_ instance: String) -> String { "\(instance).showsSeconds" }
        static func showsDate(_ instance: String) -> String { "\(instance).showsDate" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
        static func timeZone(_ instance: String) -> String { "\(instance).timeZone" }
    }

    static var current: ClockSettings { current("clock") }

    static func current(_ instance: String) -> ClockSettings {
        let store = SettingsStore.shared
        let defaults = ClockSettings()
        return ClockSettings(
            style: Style(rawValue: store.string(Key.style(instance), or: defaults.style.rawValue)) ?? defaults.style,
            hourFormat: HourFormat(rawValue: store.string(Key.hourFormat(instance), or: defaults.hourFormat.rawValue)) ?? defaults.hourFormat,
            showsSeconds: store.bool(Key.showsSeconds(instance), or: defaults.showsSeconds),
            showsDate: store.bool(Key.showsDate(instance), or: defaults.showsDate),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex),
            timeZoneID: store.string(Key.timeZone(instance), or: defaults.timeZoneID)
        )
    }

    func save(_ instance: String = "clock") {
        SettingsStore.shared.set([
            Key.style(instance): style.rawValue,
            Key.hourFormat(instance): hourFormat.rawValue,
            Key.showsSeconds(instance): showsSeconds,
            Key.showsDate(instance): showsDate,
            Key.accent(instance): accentHex,
            Key.timeZone(instance): timeZoneID,
        ])
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
