import AppKit

/// Builds the widget views the notch panel shows, from the same classes the
/// Dock bars use.
enum NotchWidgets {
    /// Listeners held for as long as the agent runs.
    private static var playbackTokens: [UUID] = []

    static func view(for instance: String) -> BarContentView? {
        let made: BarContentView?
        switch WidgetInstance.kind(of: instance) {
        case "nowplaying":
            let view = BarView(frame: .zero)
            view.onCommand = { NowPlayingControl.send($0) }
            playbackTokens.append(NowPlayingSource.shared.addListener { [weak view] state in
                view?.state = state
            })
            made = view
        case "sensors":
            made = SensorsBarView(frame: .zero)
        case "disks":
            made = DisksBarView(frame: .zero)
        case "actions":
            let view = ActionsBarView(frame: .zero)
            view.onRun = { runAction($0) }
            made = view
        case "note":
            made = NoteBarView(frame: .zero)
        case "calendar":
            let view = CalendarBarView(frame: .zero)
            view.onOpen = {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
            made = view
        case "weather":
            made = WeatherBarView(frame: .zero)
        case "shelf":
            let view = ShelfBarView(frame: .zero)
            view.onOpen = { NSWorkspace.shared.open($0) }
            made = view
        case "applenotes":
            let view = AppleNotesBarView(frame: .zero)
            view.onOpen = { note in note.map(AppleNotesBridge.open) ?? AppleNotesBridge.openApp() }
            view.onCreate = { AppleNotesBridge.createNote(in: AppleNotesSettings.current.folder) }
            made = view
        default:
            made = nil
        }
        guard let made else { return nil }
        made.instance = instance
        made.forcesDarkContent = true
        // Stacked rows: every one the same size, whatever it holds.
        made.fillsHeight = true
        // How many cells this copy asks for — the same setting the Dock bars
        // use for their width, read from this copy rather than the template.
        made.tileCount = cellCount(for: instance)
        made.verticalSlots = NotchSettings.span(of: instance)
        made.reloadSettings()
        return made
    }

    static func cellCount(for instance: String) -> Int {
        let template: BarLayout.Spec?
        switch WidgetInstance.kind(of: instance) {
        case "nowplaying": template = BarLayout.nowPlaying
        case "sensors": template = BarLayout.sensors
        case "disks": template = BarLayout.disks
        case "actions": template = BarLayout.actions
        case "note": template = BarLayout.note
        case "shelf": template = BarLayout.shelf
        case "calendar": template = BarLayout.calendar
        case "weather": template = BarLayout.weather
        default: template = nil
        }
        guard let template else { return 4 }
        return template.forInstance(instance, anchorTitle: "").spacerCount + 1
    }
}
