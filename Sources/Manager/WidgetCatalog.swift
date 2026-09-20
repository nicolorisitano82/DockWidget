import AppKit

/// One copy of one widget: what the Dock pins, what the settings belong to,
/// and what the manager shows.
struct WidgetDescriptor {
    let kind: String
    /// 1, 2, 3 — the same widget configured differently each time.
    let copy: Int
    /// The base name of the app bundle the build produces: "Orologio".
    let bundleBase: String
    let baseName: String
    let summary: String
    let symbol: String
    let paneFactory: (String) -> PaneViewController

    /// Settings prefix and bundle suffix: "clock", "clock2"…
    var id: String { WidgetInstance.id(kind: kind, copy: copy) }
    var bundleID: String { "dev.nicolo.dockwidgets.\(id)" }
    var helperBundleName: String { WidgetInstance.bundleName(base: bundleBase, copy: copy) }
    /// What the Dock calls the tile, which is what the overlay anchors to.
    var anchorTitle: String { WidgetInstance.anchorTitle(base: bundleBase, copy: copy) }

    var name: String { copy <= 1 ? baseName : "\(baseName) \(copy)" }

    var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Widgets", isDirectory: true)
            .appendingPathComponent(helperBundleName, isDirectory: true)
    }

    var isInstalled: Bool { DockTiles.contains(self) }

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
                 symbol: "music.note") { NowPlayingPaneController(instance: $0) },
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
        template(kind: "actions", bundle: "Azioni", name: T("Azioni", "Actions"),
                 summary: T("Quattro celle: un'icona, i tuoi colori, un'azione a testa.",
                            "Four cells: an icon, your colours, an action each."),
                 symbol: "square.grid.2x2.fill") { ActionsPaneController(instance: $0) },
    ]

    /// Every copy of every widget, whether or not it is in the Dock.
    static var all: [WidgetDescriptor] {
        kinds.flatMap { copies(of: $0) }
    }

    static func copies(of kind: WidgetDescriptor) -> [WidgetDescriptor] {
        (1...WidgetInstance.maximumCopies).map { copy in
            WidgetDescriptor(kind: kind.kind, copy: copy, bundleBase: kind.bundleBase,
                             baseName: kind.baseName, summary: kind.summary,
                             symbol: kind.symbol, paneFactory: kind.paneFactory)
        }.filter(\.exists)
    }

    static func widget(id: String) -> WidgetDescriptor? {
        all.first { $0.id == id }
    }

    private static func template(kind: String, bundle: String, name: String, summary: String,
                                 symbol: String,
                                 pane: @escaping (String) -> PaneViewController) -> WidgetDescriptor {
        WidgetDescriptor(kind: kind, copy: 1, bundleBase: bundle, baseName: name,
                         summary: summary, symbol: symbol, paneFactory: pane)
    }
}
