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
            name: "Orologio",
            summary: "Cinque quadranti, con secondi e data.",
            helperBundleName: "Orologio.app",
            symbol: "clock.fill",
            barSpec: { nil },
            makePane: { ClockPaneController() }
        ),
        WidgetDescriptor(
            id: "nowplaying",
            name: "In riproduzione",
            summary: "Copertina, stato della riproduzione e avanzamento del brano.",
            helperBundleName: "NowPlaying.app",
            symbol: "music.note",
            barSpec: { NowPlayingSettings.current.mode == .bar ? BarLayout.nowPlaying : nil },
            makePane: { NowPlayingPaneController() }
        ),
        WidgetDescriptor(
            id: "sensors",
            name: "Sensori",
            summary: "CPU, memoria, disco, rete, batteria: uno per tile.",
            helperBundleName: "Sensori.app",
            symbol: "gauge.with.dots.needle.bottom.50percent",
            barSpec: { SensorsSettings.current.mode == .bar ? BarLayout.sensors : nil },
            makePane: { SensorsPaneController() }
        ),
        WidgetDescriptor(
            id: "actions",
            name: "Azioni",
            summary: "Quattro celle: un'icona, i tuoi colori, un'azione a testa.",
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
