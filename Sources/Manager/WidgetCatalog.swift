import AppKit

/// One copy of one widget: what the Dock pins, what the settings belong to,
/// and what the manager shows.
/// Where a widget lives. Most sit in the Dock; the notch bar is its own place
/// and has no tile to pin.
enum WidgetSurface {
    case dock
    case notch
}

struct WidgetDescriptor {
    let kind: String
    /// 1, 2, 3 — the same widget configured differently each time.
    let copy: Int
    /// The base name of the app bundle the build produces: "Orologio".
    let bundleBase: String
    let baseName: String
    let summary: String
    let symbol: String
    /// Whether a second copy would say something different from the first.
    ///
    /// The rule is about meaning, not mechanics: a widget can be multiplied
    /// when each copy has a subject of its own — a time zone, a folder, a
    /// volume, a note, a set of actions. One that reports the single thing the
    /// machine is doing cannot: two now-playing widgets would say the same
    /// thing twice.
    let isReplicable: Bool
    let surface: WidgetSurface
    /// True when this descriptor stands for the widget's place in the notch
    /// rather than a tile in the Dock.
    var isInNotch = false
    let paneFactory: (String) -> PaneViewController

    /// Settings prefix and bundle suffix: "clock", "clock2", "clock@notch"…
    var id: String {
        isInNotch ? WidgetInstance.notchID(kind: kind) : WidgetInstance.id(kind: kind, copy: copy)
    }
    var bundleID: String { "dev.nicolo.underdock.\(id)" }
    var helperBundleName: String { WidgetInstance.bundleName(base: bundleBase, copy: copy) }
    /// What the Dock calls the tile, which is what the overlay anchors to.
    var anchorTitle: String { WidgetInstance.anchorTitle(base: bundleBase, copy: copy) }

    var name: String { copy <= 1 ? baseName : "\(baseName) \(copy)" }

    /// The first copy ships inside the app; the others are made on demand and
    /// live outside it, where replacing the app cannot take them away.
    var helperURL: URL {
        copy <= 1
            ? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/Widgets", isDirectory: true)
                .appendingPathComponent(helperBundleName, isDirectory: true)
            : WidgetInstance.copiesDirectory
                .appendingPathComponent(helperBundleName, isDirectory: true)
    }

    /// The same widget, as it appears in the notch.
    var inNotch: WidgetDescriptor {
        var copy = self
        copy.isInNotch = true
        return copy
    }

    /// The same widget, as another copy of itself.
    func copy(number: Int) -> WidgetDescriptor {
        WidgetDescriptor(kind: kind, copy: number, bundleBase: bundleBase, baseName: baseName,
                         summary: summary, symbol: symbol, isReplicable: isReplicable,
                         surface: surface, paneFactory: paneFactory)
    }

    var isInstalled: Bool {
        isInNotch ? NotchSettings.current.widgets.contains(id) : DockTiles.contains(self)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: helperURL.path) }

    var icon: NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration)
            ?? NSWorkspace.shared.icon(forFile: helperURL.path)
    }

    func makePane() -> PaneViewController { paneFactory(id) }

    /// The overlay this copy uses, when it is showing as a bar. Each copy
    /// anchors to its own tile and owns its own spacers.
    var barSpec: BarLayout.Spec? {
        func spec(_ template: BarLayout.Spec) -> BarLayout.Spec {
            template.forInstance(id, anchorTitle: anchorTitle)
        }
        switch kind {
        case "nowplaying":
            return NowPlayingSettings.current(id).mode == .bar ? spec(BarLayout.nowPlaying) : nil
        case "sensors":
            return SensorsSettings.current(id).mode == .bar ? spec(BarLayout.sensors) : nil
        case "disks":
            return DisksSettings.current(id).mode == .bar ? spec(BarLayout.disks) : nil
        case "actions":
            return spec(BarLayout.actions)
        case "note":
            return spec(BarLayout.note)
        case "shelf":
            return spec(BarLayout.shelf)
        case "calendar":
            return spec(BarLayout.calendar)
        case "weather":
            return spec(BarLayout.weather)
        default:
            return nil
        }
    }
}

enum WidgetCatalog {
    /// The widgets themselves, one entry each. Copies are made from these.
    static let kinds: [WidgetDescriptor] = [
        template(kind: "clock", bundle: "Orologio", name: T("Orologio", "Clock"),
                 summary: T("Sei quadranti, con secondi, data e fuso orario.",
                            "Six faces, with seconds, date and time zone."),
                 symbol: "clock.fill") { ClockPaneController(instance: $0) },
        template(kind: "nowplaying", bundle: "NowPlaying", name: T("In riproduzione", "Now Playing"),
                 summary: T("Copertina, stato della riproduzione e avanzamento del brano.",
                            "Cover art, playback state and track progress."),
                 symbol: "music.note", replicable: false) { NowPlayingPaneController(instance: $0) },
        template(kind: "note", bundle: "Appunto", name: T("Appunto", "Note"),
                 summary: T("Due righe da tenere sott'occhio, che si aprono in un click.",
                            "A couple of lines kept in sight, one click from being edited."),
                 symbol: "note.text") { NotePaneController(instance: $0) },
        template(kind: "folder", bundle: "Cartella", name: T("Cartella", "Folder"),
                 summary: T("Una cartella viva: quello che contiene, e i file che ci trascini sopra.",
                            "A folder that stays alive: what is in it, and the files you drop on it."),
                 symbol: "folder.fill") { FolderPaneController(instance: $0) },
        template(kind: "disks", bundle: "Dischi", name: T("Dischi", "Disks"),
                 summary: T("Spazio per volume, e le unità esterne appena le colleghi.",
                            "Space per volume, and external drives the moment you plug them in."),
                 symbol: "internaldrive.fill") { DisksPaneController(instance: $0) },
        template(kind: "sensors", bundle: "Sensori", name: T("Sensori", "Sensors"),
                 summary: T("CPU, memoria, disco, rete, batteria: uno per tile.",
                            "CPU, memory, disk, network, battery: one per tile."),
                 symbol: "gauge.with.dots.needle.bottom.50percent") { SensorsPaneController(instance: $0) },
        template(kind: "applenotes", bundle: "Note", name: T("Note di Apple", "Apple Notes"),
                 summary: T("L'ultima nota di Note, con un tasto per scriverne una nuova.",
                            "The latest note from Notes, with a button to start a new one."),
                 symbol: "note.text.badge.plus") { AppleNotesPaneController(instance: $0) },
        template(kind: "calendar", bundle: "Appuntamenti",
                 name: T("Appuntamenti", "Appointments"),
                 summary: T("Quello che c'è adesso e quello che viene dopo, dal calendario di Apple o da un indirizzo iCal di Google.",
                            "What is on now and what comes next, from Apple Calendar or from a Google iCal address."),
                 symbol: "calendar") { CalendarPaneController(instance: $0) },
        template(kind: "weather", bundle: "Meteo", name: T("Meteo", "Weather"),
                 summary: T("Che tempo fa dove hai detto tu, con minima e massima di oggi.",
                            "The weather where you said, with today's low and high."),
                 symbol: "cloud.sun.fill") { WeatherPaneController(instance: $0) },
        template(kind: "shelf", bundle: "Mensola", name: T("Mensola", "Shelf"),
                 summary: T("Dove posare un file per un minuto: resta lì e lo riprendi trascinandolo.",
                            "Somewhere to put a file down for a minute: it stays there and you drag it back out."),
                 symbol: "tray.full.fill") { ShelfPaneController(instance: $0) },
        template(kind: "actions", bundle: "Azioni", name: T("Azioni", "Actions"),
                 summary: T("Quattro celle: un'icona, i tuoi colori, un'azione a testa.",
                            "Four cells: an icon, your colours, an action each."),
                 symbol: "square.grid.2x2.fill") { ActionsPaneController(instance: $0) },
        template(kind: "notch", bundle: "Notch", name: T("Notch", "Notch"),
                 summary: T("Una striscia che scende dal notch quando ci passi sopra.",
                            "A strip that comes down from the notch when the pointer arrives."),
                 symbol: "rectangle.topthird.inset.filled",
                 replicable: false, surface: .notch) { NotchPaneController(instance: $0) },
    ]

    /// Every copy of every widget, whether or not it is in the Dock.
    static var all: [WidgetDescriptor] {
        kinds.flatMap { copies(of: $0) }
    }

    static func copies(of kind: WidgetDescriptor) -> [WidgetDescriptor] {
        guard kind.isReplicable else { return [kind] }
        return WidgetInstances.all(of: kind.kind).map { kind.copy(number: WidgetInstance.copy(of: $0)) }
    }

    /// Everywhere this widget currently sits: its copies in the Dock, and the
    /// notch when it has been put there.
    static func placements(of kind: WidgetDescriptor) -> [WidgetDescriptor] {
        var list = kind.surface == .dock ? copies(of: kind) : [kind]
        if NotchOffer.all.contains(WidgetInstance.notchID(kind: kind.kind)),
           NotchSettings.current.widgets.contains(WidgetInstance.notchID(kind: kind.kind)) {
            list.append(kind.inNotch)
        }
        return list
    }

    static func widget(id: String) -> WidgetDescriptor? {
        all.first { $0.id == id }
    }

    private static func template(kind: String, bundle: String, name: String, summary: String,
                                 symbol: String, replicable: Bool = true,
                                 surface: WidgetSurface = .dock,
                                 pane: @escaping (String) -> PaneViewController) -> WidgetDescriptor {
        WidgetDescriptor(kind: kind, copy: 1, bundleBase: bundle, baseName: name,
                         summary: summary, symbol: symbol, isReplicable: replicable,
                         surface: surface, paneFactory: pane)
    }
}
