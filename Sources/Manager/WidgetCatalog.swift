import AppKit

/// One entry per widget the manager can put in the Dock.
struct WidgetDescriptor {
    let id: String
    let name: String
    let summary: String
    /// Bundle name under `DockWidgets.app/Contents/Library/Widgets`.
    let helperBundleName: String
    /// Shown in the sidebar. An SF Symbol rather than the helper's app icon,
    /// which is a picture of the widget and reads as noise at 22 points.
    let symbol: String
    /// The overlay this widget uses, when it is showing as a bar.
    let barSpec: () -> BarLayout.Spec?
    let makePane: () -> PaneViewController

    var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Widgets", isDirectory: true)
            .appendingPathComponent(helperBundleName, isDirectory: true)
    }

    /// Matches the identifier the build script gives the widget's app bundle.
    var bundleID: String { "dev.nicolo.dockwidgets.\(id)" }

    var isInstalled: Bool { DockTiles.contains(self) }

    var icon: NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration)
            ?? NSWorkspace.shared.icon(forFile: helperURL.path)
    }
}

enum WidgetCatalog {
    static let all: [WidgetDescriptor] = [
        WidgetDescriptor(
            id: "clock",
            name: T("Orologio", "Clock"),
            summary: T("Cinque quadranti, con secondi e data.", "Six faces, with seconds and date."),
            helperBundleName: "Orologio.app",
            symbol: "clock.fill",
            barSpec: { nil },
            makePane: { ClockPaneController() }
        ),
        WidgetDescriptor(
            id: "nowplaying",
            name: T("In riproduzione", "Now Playing"),
            summary: T("Copertina, stato della riproduzione e avanzamento del brano.", "Cover art, playback state and track progress."),
            helperBundleName: "NowPlaying.app",
            symbol: "music.note",
            barSpec: { NowPlayingSettings.current.mode == .bar ? BarLayout.nowPlaying : nil },
            makePane: { NowPlayingPaneController() }
        ),
        WidgetDescriptor(
            id: "sensors",
            name: T("Sensori", "Sensors"),
            summary: T("CPU, memoria, disco, rete, batteria: uno per tile.", "CPU, memory, disk, network, battery: one per tile."),
            helperBundleName: "Sensori.app",
            symbol: "gauge.with.dots.needle.bottom.50percent",
            barSpec: { SensorsSettings.current.mode == .bar ? BarLayout.sensors : nil },
            makePane: { SensorsPaneController() }
        ),
        WidgetDescriptor(
            id: "folder",
            name: T("Cartella", "Folder"),
            summary: T("Una cartella viva: quello che contiene, e i file che ci trascini sopra.",
                       "A folder that stays alive: what is in it, and the files you drop on it."),
            helperBundleName: "Cartella.app",
            symbol: "folder.fill",
            barSpec: { nil },
            makePane: { FolderPaneController() }
        ),
        WidgetDescriptor(
            id: "disks",
            name: T("Dischi", "Disks"),
            summary: T("Spazio per volume, e le unità esterne appena le colleghi.",
                       "Space per volume, and external drives the moment you plug them in."),
            helperBundleName: "Dischi.app",
            symbol: "internaldrive.fill",
            barSpec: { DisksSettings.current.mode == .bar ? BarLayout.disks : nil },
            makePane: { DisksPaneController() }
        ),
        WidgetDescriptor(
            id: "actions",
            name: T("Azioni", "Actions"),
            summary: T("Quattro celle: un'icona, i tuoi colori, un'azione a testa.", "Four cells: an icon, your colours, an action each."),
            helperBundleName: "Azioni.app",
            symbol: "square.grid.2x2.fill",
            barSpec: { BarLayout.actions },
            makePane: { ActionsPaneController() }
        ),
    ]

    static func widget(id: String) -> WidgetDescriptor? {
        all.first { $0.id == id }
    }
}
