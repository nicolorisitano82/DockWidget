import Foundation

/// Reads an iCalendar feed — the secret address a Google calendar gives you —
/// and turns it into appointments.
///
/// A whole iCalendar implementation is a large thing; this is the part a widget
/// needs: what is on, and when. Timed and all-day events, the common repeats
/// (daily, weekly with weekdays, monthly, yearly) with their interval, count
/// and end, and the dates struck out of a repeat. Anything it does not
/// understand it leaves out rather than guesses at.
enum ICSFeed {

    // MARK: Fetching

    static func load(_ address: String, within window: DateInterval,
                     completion: @escaping ([CalendarEvent]) -> Void) {
        // Google hands out webcal:// addresses, which are https with a hat on.
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        }
        guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else {
            Diagnostics.once("ics-url", "indirizzo iCal non valido: \(address)")
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Diagnostics.once("ics-fetch", "iCal non raggiungibile: \(error.localizedDescription)")
                completion([])
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Diagnostics.once("ics-status", "iCal ha risposto \(http.statusCode)")
                completion([])
                return
            }
            guard let data, let body = String(data: data, encoding: .utf8) else {
                completion([])
                return
            }
            completion(parse(body, within: window))
        }.resume()
    }

    // MARK: Parsing

    static func parse(_ text: String, within window: DateInterval) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        for block in blocks(in: unfold(text)) {
            events.append(contentsOf: expand(block, within: window))
        }
        return events.sorted { $0.start < $1.start }
    }

    /// A line broken across several is continued by a leading space or tab.
    private static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(raw)
            }
        }
        return lines
    }

    private struct Block {
        var summary = ""
        var location = ""
        var start: Date?
        var end: Date?
        var isAllDay = false
        var rule: String?
        var excluded: [Date] = []
    }

    private static func blocks(in lines: [String]) -> [Block] {
        var found: [Block] = []
        var current: Block?
        for line in lines {
            if line.hasPrefix("BEGIN:VEVENT") {
                current = Block()
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                if let current, current.start != nil { found.append(current) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...])
            let name = head.components(separatedBy: ";")[0].uppercased()

            switch name {
            case "SUMMARY": current?.summary = unescape(value)
            case "LOCATION": current?.location = unescape(value)
            case "DTSTART":
                current?.start = date(value, parameters: head)
                current?.isAllDay = head.uppercased().contains("VALUE=DATE")
                    && !head.uppercased().contains("DATE-TIME")
            case "DTEND": current?.end = date(value, parameters: head)
            case "RRULE": current?.rule = value
            case "EXDATE":
                for piece in value.components(separatedBy: ",") {
                    if let when = date(piece, parameters: head) { current?.excluded.append(when) }
                }
            default: break
            }
        }
        return found
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func date(_ value: String, parameters: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespaces)
        var zone = TimeZone.autoupdatingCurrent
        if let range = parameters.uppercased().range(of: "TZID=") {
            let name = parameters[range.upperBound...].components(separatedBy: ";")[0]
            if let found = TimeZone(identifier: String(name)) { zone = found }
        }
        if text.hasSuffix("Z") { zone = TimeZone(identifier: "UTC") ?? zone }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        for format in ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let when = formatter.date(from: text) { return when }
        }
        return nil
    }

    // MARK: Repeats

    private static func expand(_ block: Block, within window: DateInterval) -> [CalendarEvent] {
        guard let start = block.start else { return [] }
        let length = (block.end ?? start.addingTimeInterval(block.isAllDay ? 86_400 : 3_600))
            .timeIntervalSince(start)

        func make(_ when: Date) -> CalendarEvent {
            CalendarEvent(title: block.summary.isEmpty ? T("Senza titolo", "Untitled")
                                                       : block.summary,
                          start: when, end: when.addingTimeInterval(max(length, 60)),
                          isAllDay: block.isAllDay, location: block.location, tint: nil)
        }

        guard let rule = block.rule else {
            let event = make(start)
            return window.intersects(DateInterval(start: event.start, end: event.end))
                ? [event] : []
        }

        var parts: [String: String] = [:]
        for piece in rule.components(separatedBy: ";") {
            let halves = piece.components(separatedBy: "=")
            guard halves.count == 2 else { continue }
            parts[halves[0].uppercased()] = halves[1]
        }
        guard let frequency = parts["FREQ"]?.uppercased() else { return [] }
        let interval = max(Int(parts["INTERVAL"] ?? "1") ?? 1, 1)
        let limit = Int(parts["COUNT"] ?? "")
        let until = parts["UNTIL"].flatMap { date($0, parameters: "") }
        let weekdays = (parts["BYDAY"] ?? "").components(separatedBy: ",")
            .compactMap(weekday(from:))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        var results: [CalendarEvent] = []
        var cursor = start
        var made = 0
        // A cap, not a schedule: a daily repeat with no end would otherwise be
        // walked for ever when the window is far away.
        for _ in 0..<2_000 {
            if let until, cursor > until { break }
            if let limit, made >= limit { break }
            if cursor > window.end { break }

            var occurrences = [cursor]
            if frequency == "WEEKLY", !weekdays.isEmpty {
                occurrences = weekdays.compactMap { day in
                    calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: cursor)!,
                                      matching: DateComponents(hour: calendar.component(.hour, from: start),
                                                               minute: calendar.component(.minute, from: start),
                                                               weekday: day),
                                      matchingPolicy: .nextTime)
                }
            }

            for when in occurrences {
                made += 1
                if let limit, made > limit { break }
                guard !block.excluded.contains(where: { abs($0.timeIntervalSince(when)) < 60 })
                else { continue }
                let event = make(when)
                guard window.intersects(DateInterval(start: event.start, end: event.end))
                else { continue }
                results.append(event)
            }

            let step: Calendar.Component
            switch frequency {
            case "DAILY": step = .day
            case "WEEKLY": step = .weekOfYear
            case "MONTHLY": step = .month
            case "YEARLY": step = .year
            default: return results
            }
            guard let next = calendar.date(byAdding: step, value: interval, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    private static func weekday(from code: String) -> Int? {
        // A BYDAY can carry an ordinal — "2FR", the second Friday. The day is
        // what is used here; the ordinal is left to the calendar app.
        let letters = String(code.suffix(2)).uppercased()
        switch letters {
        case "SU": return 1
        case "MO": return 2
        case "TU": return 3
        case "WE": return 4
        case "TH": return 5
        case "FR": return 6
        case "SA": return 7
        default: return nil
        }
    }
}
