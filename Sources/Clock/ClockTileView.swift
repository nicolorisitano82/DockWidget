import AppKit

final class ClockTileView: TileView {
    private var settings = ClockSettings.current
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private var localeObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rebuildFormatters()
        for name in [NSLocale.currentLocaleDidChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuildFormatters()
                self?.needsDisplay = true
            }
            localeObservers.append(token)
        }
    }

    deinit {
        localeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Pinned instant used when rendering app icons, where "now" would be wrong.
    var fixedDate: Date?

    private var renderDate: Date { fixedDate ?? Date() }

    override func reloadSettings() {
        settings = ClockSettings.current
        accent = settings.accent
        rebuildFormatters()
        needsDisplay = true
    }

    private func rebuildFormatters() {
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.timeZone = settings.timeZone
        timeFormatter.dateFormat = settings.timeFormat()

        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = settings.timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("EEE d")
    }

    /// What the tile currently shows, so the plug-in can skip redraws that would
    /// paint the same pixels.
    func renderToken(at date: Date = Date()) -> Int {
        let unit: TimeInterval = settings.showsSeconds ? 1 : 60
        return Int(date.timeIntervalSince1970 / unit)
    }

    var formattedTime: String { timeFormatter.string(from: Date()) }

    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let now = renderDate
        settings.style.face.draw(ClockFaceContext(
            card: card,
            date: now,
            settings: settings,
            palette: palette,
            timeText: timeFormatter.string(from: now),
            dateText: dateFormatter.string(from: now)
        ))
    }
}
