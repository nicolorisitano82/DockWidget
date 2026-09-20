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
            view.onCommand = { NowPlayingFeed.send($0) }
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
            view.onRun = { ActionRunner.run($0) }
            made = view
        case "note":
            made = NoteBarView(frame: .zero)
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
        // A notch row is about four Dock tiles wide; the height clamps the rest.
        made.tileCount = 4
        made.reloadSettings()
        return made
    }

    /// What can be put in the notch, as instance identifiers.
    static let offered: [String] = ["nowplaying", "sensors", "disks", "actions", "note", "applenotes"]
}
