import AppKit

struct CalendarSettings: Equatable {
    /// Where the appointments come from.
    ///
    /// Apple's own store covers every account the Mac has been told about,
    /// Google included, because adding a Google account in System Settings puts
    /// its calendars there. The feed is for the other case: a Google calendar
    /// this Mac does not have an account for, reached by its own secret
    /// address, which is read-only and needs nothing signing in.
    enum Source: String, CaseIterable {
        case apple, feed

        var label: String {
            switch self {
            case .apple: return T("Calendario di Apple", "Apple Calendar")
            case .feed: return T("Indirizzo iCal (Google)", "iCal address (Google)")
            }
        }
    }

    var source: Source = .apple
    /// The secret iCal address, from Google Calendar → Settings → Integrate
    /// calendar → Secret address in iCal format.
    var feedURL = ""
    /// How far ahead to look.
    var daysAhead = 7
    /// Whether the one that has already started still counts as next.
    var showsCurrent = true
    var showsLocation = false
    var accentHex = "#FF453A"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemRed }

    enum Key {
        static func source(_ instance: String) -> String { "\(instance).source" }
        static func feed(_ instance: String) -> String { "\(instance).feed" }
        static func daysAhead(_ instance: String) -> String { "\(instance).daysAhead" }
        static func showsCurrent(_ instance: String) -> String { "\(instance).showsCurrent" }
        static func showsLocation(_ instance: String) -> String { "\(instance).showsLocation" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: CalendarSettings { current("calendar") }

    static func current(_ instance: String) -> CalendarSettings {
        let store = SettingsStore.shared
        let defaults = CalendarSettings()
        return CalendarSettings(
            source: Source(rawValue: store.string(Key.source(instance),
                                                  or: defaults.source.rawValue)) ?? defaults.source,
            feedURL: store.string(Key.feed(instance), or: defaults.feedURL),
            daysAhead: max(1, min(Int(store.double(Key.daysAhead(instance),
                                                   or: Double(defaults.daysAhead))), 60)),
            showsCurrent: store.bool(Key.showsCurrent(instance), or: defaults.showsCurrent),
            showsLocation: store.bool(Key.showsLocation(instance), or: defaults.showsLocation),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "calendar") {
        SettingsStore.shared.set([
            Key.source(instance): source.rawValue,
            Key.feed(instance): feedURL,
            Key.daysAhead(instance): Double(daysAhead),
            Key.showsCurrent(instance): showsCurrent,
            Key.showsLocation(instance): showsLocation,
            Key.accent(instance): accentHex,
        ])
    }
}

/// One appointment, whichever calendar it came from.
struct CalendarEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    /// The colour the calendar it belongs to is drawn in, when there is one.
    var tint: NSColor?

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.title == rhs.title && lhs.start == rhs.start
            && lhs.end == rhs.end && lhs.isAllDay == rhs.isAllDay
    }

    var isRunning: Bool {
        let now = Date()
        return start <= now && end > now
    }

    /// "09:30", or the day when it is not today.
    func when(calendar: Calendar = .autoupdatingCurrent) -> String {
        if isAllDay {
            return calendar.isDateInToday(start)
                ? T("oggi", "today")
                : shortDay(calendar: calendar)
        }
        let time = DateFormatter()
        time.locale = .autoupdatingCurrent
        time.setLocalizedDateFormatFromTemplate("jm")
        guard calendar.isDateInToday(start) else {
            return "\(shortDay(calendar: calendar)) \(time.string(from: start))"
        }
        return time.string(from: start)
    }

    private func shortDay(calendar: Calendar) -> String {
        if calendar.isDateInTomorrow(start) { return T("domani", "tomorrow") }
        let day = DateFormatter()
        day.locale = .autoupdatingCurrent
        day.setLocalizedDateFormatFromTemplate(
            calendar.isDate(start, equalTo: Date(), toGranularity: .weekOfYear) ? "EEE" : "dMMM")
        return day.string(from: start)
    }

    /// "fra 20 min", "ora", "fra 2 h".
    var countdown: String {
        if isRunning { return T("ora", "now") }
        let seconds = start.timeIntervalSinceNow
        guard seconds > 0 else { return T("passato", "past") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return T("fra \(max(minutes, 1)) min", "in \(max(minutes, 1)) min") }
        let hours = minutes / 60
        if hours < 24 { return T("fra \(hours) h", "in \(hours) h") }
        return T("fra \(hours / 24) g", "in \(hours / 24) d")
    }
}
