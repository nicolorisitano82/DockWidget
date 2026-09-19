import AppKit

/// One entry per widget the manager can put in the Dock.
struct WidgetDescriptor {
    let id: String
    let name: String
    let summary: String
    /// Bundle name under `DockWidgets.app/Contents/Library/Widgets`.
    let helperBundleName: String
    let makePane: () -> PaneViewController

    var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Widgets", isDirectory: true)
            .appendingPathComponent(helperBundleName, isDirectory: true)
    }

    var isInstalled: Bool { DockTiles.contains(helperURL) }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: helperURL.path)
    }
}

enum WidgetCatalog {
    static let all: [WidgetDescriptor] = [
        WidgetDescriptor(
            id: "clock",
            name: "Orologio",
            summary: "Quadrante analogico o digitale, con secondi e data.",
            helperBundleName: "Orologio.app",
            makePane: { ClockPaneController() }
        ),
        WidgetDescriptor(
            id: "nowplaying",
            name: "In riproduzione",
            summary: "Copertina, stato della riproduzione e avanzamento del brano.",
            helperBundleName: "NowPlaying.app",
            makePane: { NowPlayingPaneController() }
        ),
    ]

    static func widget(id: String) -> WidgetDescriptor? {
        all.first { $0.id == id }
    }
}
