import AppKit
import EventKit

/// Keeps one widget's list of appointments up to date.
///
/// One store per copy, because two calendar widgets can be pointed at two
/// different places — one at the Mac's own calendars, one at a Google address.
///
/// Reading Apple's calendars asks the user's permission, and the request has to
/// come from an app the user can recognise in System Settings. So it happens
/// here, in our own process, and never inside the Dock's plug-in host — which
/// is also why this widget is a bar rather than a tile.
final class CalendarStore {
    private static var stores: [String: CalendarStore] = [:]

    static func shared(_ instance: String) -> CalendarStore {
        if let existing = stores[instance] { return existing }
        let store = CalendarStore(instance: instance)
        stores[instance] = store
        return store
    }

    let instance: String
    private(set) var events: [CalendarEvent] = []
    /// Nil while nothing has gone wrong; a line to show instead of the list.
    private(set) var problem: String?

    private let eventStore = EKEventStore()
    private var listeners: [UUID: () -> Void] = [:]
    private var timer: Timer?
    private var isAsking = false
    private var lastSignature = ""

    private init(instance: String) {
        self.instance = instance
    }

    var settings: CalendarSettings { .current(instance) }

    @discardableResult
    func addListener(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        start()
        handler()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        // Five minutes: an appointment does not move often, and the countdown
        // beside it is redrawn by the panel's own beat anyway.
        let ticker = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        ticker.tolerance = 30
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .EKEventStoreChanged, object: eventStore)
        reload()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged,
                                                  object: eventStore)
    }

    @objc private func storeChanged() { reload() }

    /// Called when the settings change: the source may now be somewhere else.
    func refresh() { reload() }

    private var window: DateInterval {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let from = settings.showsCurrent
            ? calendar.startOfDay(for: now)
            : now
        let to = calendar.date(byAdding: .day, value: settings.daysAhead, to: now) ?? now
        return DateInterval(start: from, end: max(to, from.addingTimeInterval(60)))
    }

    private func reload() {
        switch settings.source {
        case .apple: reloadFromApple()
        case .feed: reloadFromFeed()
        }
    }

    // MARK: Apple

    private func reloadFromApple() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            readApple()
        case .notDetermined:
            ask()
        case .denied, .restricted, .writeOnly:
            publish([], problem: T("Accesso al calendario negato. Impostazioni di Sistema → Privacy e Sicurezza → Calendari.",
                                   "Calendar access denied. System Settings → Privacy & Security → Calendars."))
        @unknown default:
            readApple()
        }
    }

    private func ask() {
        guard !isAsking else { return }
        isAsking = true
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAsking = false
                granted ? self.readApple() : self.reloadFromApple()
            }
        }
    }

    private func readApple() {
        let span = window
        let predicate = eventStore.predicateForEvents(withStart: span.start, end: span.end,
                                                      calendars: nil)
        let found = eventStore.events(matching: predicate).map { event in
            CalendarEvent(title: event.title ?? T("Senza titolo", "Untitled"),
                          start: event.startDate,
                          end: event.endDate ?? event.startDate.addingTimeInterval(3_600),
                          isAllDay: event.isAllDay,
                          location: event.location ?? "",
                          tint: event.calendar?.color)
        }
        publish(found, problem: nil)
    }

    // MARK: A feed

    private func reloadFromFeed() {
        let address = settings.feedURL
        guard !address.isEmpty else {
            publish([], problem: T("Nessun indirizzo iCal.", "No iCal address yet."))
            return
        }
        ICSFeed.load(address, within: window) { [weak self] found in
            DispatchQueue.main.async {
                self?.publish(found, problem: found.isEmpty
                    ? T("Niente da quell'indirizzo.", "Nothing came back from that address.")
                    : nil)
            }
        }
    }

    // MARK: Telling everybody

    private func publish(_ found: [CalendarEvent], problem: String?) {
        let sorted = found.sorted { $0.start < $1.start }
        // Only wake the views when something actually moved: a listener that
        // redraws can come straight back here.
        let signature = sorted.prefix(6)
            .map { "\($0.title)|\($0.start.timeIntervalSince1970)" }
            .joined(separator: ";") + "|" + (problem ?? "")
        guard signature != lastSignature else { return }
        lastSignature = signature
        events = sorted
        self.problem = problem
        listeners.values.forEach { $0() }
    }

    /// What to show, newest first: the one running now, then what is coming.
    func upcoming(_ count: Int) -> [CalendarEvent] {
        let now = Date()
        let relevant = events.filter { settings.showsCurrent ? $0.end > now : $0.start > now }
        return Array(relevant.prefix(count))
    }
}
