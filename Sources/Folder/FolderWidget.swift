/// How a folder looks and opens when the Dock is the one holding it.
enum FolderStack {
    /// How the Dock lays the contents out when the stack is clicked.
    enum View: String, CaseIterable {
        case automatic, fan, grid, list

        /// The numbers the Dock writes for each of them.
        var code: Int {
            switch self {
            case .automatic: return 0
            case .fan: return 1
            case .grid: return 2
            case .list: return 3
            }
        }

        var label: String {
            switch self {
            case .automatic: return T("Automatica", "Automatic")
            case .fan: return T("Ventaglio", "Fan")
            case .grid: return T("Griglia", "Grid")
            case .list: return T("Elenco", "List")
            }
        }
    }

    enum Sort: String, CaseIterable {
        case name, dateAdded, dateModified, dateCreated, kind

        var code: Int {
            switch self {
            case .name: return 1
            case .dateAdded: return 2
            case .dateModified: return 3
            case .dateCreated: return 4
            case .kind: return 5
            }
        }

        var label: String {
            switch self {
            case .name: return T("Nome", "Name")
            case .dateAdded: return T("Data di aggiunta", "Date added")
            case .dateModified: return T("Data di modifica", "Date modified")
            case .dateCreated: return T("Data di creazione", "Date created")
            case .kind: return T("Tipo", "Kind")
            }
        }
    }

    /// Whether the tile shows the folder itself or a pile of what is in it.
    enum Display: String, CaseIterable {
        case folder, stack

        var code: Int { self == .folder ? 1 : 0 }

        var label: String {
            self == .folder ? T("Cartella", "Folder") : T("Pila", "Stack")
        }
    }
}

import AppKit

/// How the preview's list is ordered.
enum FolderSort: String, CaseIterable {
    case name, dateAdded, dateModified, kind, size

    var label: String {
        switch self {
        case .name: return T("Nome", "Name")
        case .dateAdded: return T("Data di aggiunta", "Date added")
        case .dateModified: return T("Data di modifica", "Date modified")
        case .kind: return T("Tipo", "Kind")
        case .size: return T("Dimensione", "Size")
        }
    }
}

struct FolderSettings: Equatable {
    /// What a click on the tile does.
    enum Click: String, CaseIterable {
        case preview, open

        var label: String {
            switch self {
            case .preview: return T("Apre l'anteprima", "Opens the preview")
            case .open: return T("Apre la cartella", "Opens the folder")
            }
        }
    }

    /// Whether the Dock holds our tile or its own folder stack.
    enum Place: String, CaseIterable {
        case widget, stack

        var label: String {
            self == .widget
                ? T("Widget", "Widget")
                : T("Pila di sistema", "System stack")
        }
    }

    /// Empty means no folder chosen yet.
    var path: String = ""
    var place: Place = .widget
    var stackView: FolderStack.View = .automatic
    var stackSort: FolderStack.Sort = .dateAdded
    var stackDisplay: FolderStack.Display = .folder
    var click: Click = .preview
    var showsCount = true
    var sort: FolderSort = .dateAdded
    var sortReversed = false
    var showsHidden = false
    var accentHex = "#0A84FF"
    /// Empty leaves the folder the colour the Finder gives it.
    var tintHex = ""
    /// Empty leaves it without a glyph.
    var symbol = ""

    var url: URL? { path.isEmpty ? nil : URL(fileURLWithPath: path) }
    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static func path(_ instance: String) -> String { "\(instance).path" }
        static func place(_ instance: String) -> String { "\(instance).place" }
        static func stackView(_ instance: String) -> String { "\(instance).stackView" }
        static func stackSort(_ instance: String) -> String { "\(instance).stackSort" }
        static func stackDisplay(_ instance: String) -> String { "\(instance).stackDisplay" }
        static func click(_ instance: String) -> String { "\(instance).click" }
        static func sort(_ instance: String) -> String { "\(instance).sort" }
        static func sortReversed(_ instance: String) -> String { "\(instance).sortReversed" }
        static func showsHidden(_ instance: String) -> String { "\(instance).showsHidden" }
        static func showsCount(_ instance: String) -> String { "\(instance).showsCount" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
        static func tint(_ instance: String) -> String { "\(instance).tint" }
        static func symbol(_ instance: String) -> String { "\(instance).symbol" }
    }

    static var current: FolderSettings { current("folder") }

    static func current(_ instance: String) -> FolderSettings {
        let store = SettingsStore.shared
        let defaults = FolderSettings()
        return FolderSettings(
            path: store.string(Key.path(instance), or: defaults.path),
            place: Place(rawValue: store.string(Key.place(instance),
                                                or: defaults.place.rawValue)) ?? defaults.place,
            stackView: FolderStack.View(rawValue: store.string(Key.stackView(instance),
                                                               or: defaults.stackView.rawValue))
                ?? defaults.stackView,
            stackSort: FolderStack.Sort(rawValue: store.string(Key.stackSort(instance),
                                                               or: defaults.stackSort.rawValue))
                ?? defaults.stackSort,
            stackDisplay: FolderStack.Display(rawValue: store.string(Key.stackDisplay(instance),
                                                                     or: defaults.stackDisplay.rawValue))
                ?? defaults.stackDisplay,
            click: Click(rawValue: store.string(Key.click(instance),
                                                or: defaults.click.rawValue)) ?? defaults.click,
            showsCount: store.bool(Key.showsCount(instance), or: defaults.showsCount),
            sort: FolderSort(rawValue: store.string(Key.sort(instance),
                                                    or: defaults.sort.rawValue)) ?? defaults.sort,
            sortReversed: store.bool(Key.sortReversed(instance), or: defaults.sortReversed),
            showsHidden: store.bool(Key.showsHidden(instance), or: defaults.showsHidden),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex),
            tintHex: store.string(Key.tint(instance), or: defaults.tintHex),
            symbol: store.string(Key.symbol(instance), or: defaults.symbol)
        )
    }

    func save(_ instance: String = "folder") {
        SettingsStore.shared.set([
            Key.path(instance): path,
            Key.place(instance): place.rawValue,
            Key.stackView(instance): stackView.rawValue,
            Key.stackSort(instance): stackSort.rawValue,
            Key.stackDisplay(instance): stackDisplay.rawValue,
            Key.click(instance): click.rawValue,
            Key.sort(instance): sort.rawValue,
            Key.sortReversed(instance): sortReversed,
            Key.showsHidden(instance): showsHidden,
            Key.showsCount(instance): showsCount,
            Key.accent(instance): accentHex,
            Key.tint(instance): tintHex,
            Key.symbol(instance): symbol,
        ])
    }
}

/// Watches one folder and keeps a short list of what is in it.
///
/// One monitor per copy of the widget, because two folder widgets watch two
/// different folders — and both of their plug-ins are loaded into the same
/// process.
///
/// A file descriptor source rather than a timer: the tile should change the
/// moment something lands in the folder, and stay quiet the rest of the day.
final class FolderMonitor {
    private static var monitors: [String: FolderMonitor] = [:]

    static func shared(_ instance: String) -> FolderMonitor {
        if let existing = monitors[instance] { return existing }
        let monitor = FolderMonitor(instance: instance)
        monitors[instance] = monitor
        return monitor
    }

    let instance: String

    private(set) var items: [URL] = []
    private(set) var count = 0

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    /// nil until a path has been applied — including the empty one. Deciding
    /// this from `source` instead would loop forever when no folder is chosen,
    /// because then there is no source to have.
    private var watched: String?
    private var listeners: [UUID: () -> Void] = [:]

    private init(instance: String) {
        self.instance = instance
    }

    var settings: FolderSettings { .current(instance) }

    @discardableResult
    func addListener(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        watch(settings.path)
        handler()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty { reset() }
    }

    func watch(_ path: String) {
        guard watched != path else { return }
        stop()
        watched = path
        reload()
        guard !path.isEmpty else { return }

        descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    /// Called when the last listener goes away: the next one starts fresh.
    private func reset() {
        stop()
        watched = nil
    }

    private func reload() {
        guard let url = settings.url else {
            guard !items.isEmpty || count != 0 else { return }
            items = []
            count = 0
            listeners.values.forEach { $0() }
            return
        }
        var contents: [URL] = []
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Folders like Downloads and Documents are behind TCC, and a
            // refusal looks exactly like an empty folder unless it is reported.
            Diagnostics.once("folder-read-\(url.path)",
                             "cartella \(url.path) non leggibile: \(error.localizedDescription)")
        }

        let previous = items
        // Most recent first: what just landed is what you are looking for.
        items = contents.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return left > right
        }
        // Only wake anybody when something actually moved: a listener that
        // redraws can come straight back here.
        guard items != previous || count != items.count else { return }
        count = items.count
        listeners.values.forEach { $0() }
    }
}

/// The folder as a Dock tile: its own icon, a stack of what is inside, and a
/// count.
final class FolderTileView: TileView {
    private lazy var settings = FolderSettings.current(resolvedInstance("folder"))
    private var monitor: FolderMonitor { FolderMonitor.shared(resolvedInstance("folder")) }
    private var token: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        DispatchQueue.main.async { [weak self] in self?.subscribe() }
    }

    deinit {
        if let token { monitor.removeListener(token) }
    }

    private func subscribe() {
        guard token == nil else { return }
        token = monitor.addListener { [weak self] in self?.needsDisplay = true }
    }

    override func reloadSettings() {
        settings = FolderSettings.current(resolvedInstance("folder"))
        accent = settings.accent
        subscribe()
        monitor.watch(settings.path)
        needsDisplay = true
    }

    var renderToken: String {
        "\(settings.path)|\(monitor.count)|\(settings.tintHex)|\(settings.symbol)"
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = TileGeometry.artworkRect(in: bounds)
        Diagnostics.once("folder-tile-size",
                         "tile cartella disegnata a \(Int(bounds.width))x\(Int(bounds.height)) "
                            + "punti, scala \(window?.backingScaleFactor ?? 0)")
        let side = card.width
        let palette = self.palette

        guard let url = settings.url else {
            drawCard()
            Gauge.symbol("folder.badge.questionmark",
                         in: card.insetBy(dx: side * 0.3, dy: side * 0.3),
                         color: palette.secondary)
            return
        }

        // The Finder's own icon for this folder — so a folder already
        // customised there keeps looking like itself — unless a colour or a
        // glyph has been chosen here.
        let icon = FolderIconRenderer.icon(for: url, tintHex: settings.tintHex,
                                           symbol: settings.symbol)
        icon.draw(in: card, from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: nil)

        // A Dock can be set very small — 27 points is a real setting — and
        // below that the peeking icons are noise and the badge is a speck.
        let isCompact = side < 34

        // The two most recent items peek out from behind it.
        let previews = isCompact ? [] : Array(monitor.items.prefix(2))
        for (index, item) in previews.enumerated().reversed() {
            let size = side * 0.30
            let box = NSRect(x: card.midX - size / 2 + CGFloat(index) * size * 0.42,
                             y: card.maxY - size * (0.92 + CGFloat(index) * 0.10),
                             width: size, height: size)
            let preview = NSWorkspace.shared.icon(forFile: item.path)
            preview.size = box.size
            preview.draw(in: box, from: .zero, operation: .sourceOver,
                      fraction: index == 0 ? 1 : 0.75, respectFlipped: true, hints: nil)
        }

        guard settings.showsCount, monitor.count > 0 else { return }
        let count = monitor.count
        let text = (count > 99 ? "99+" : "\(count)") as NSString
        let diameter = isCompact
            ? side * (text.length > 2 ? 0.62 : 0.54)
            : side * (text.length > 2 ? 0.40 : 0.34)
        let badge = NSRect(x: card.maxX - diameter * 0.92, y: card.maxY - diameter * 0.92,
                           width: diameter, height: diameter)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.4)
        shadow.shadowBlurRadius = diameter * 0.2
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        palette.accent.setFill()
        NSBezierPath(ovalIn: badge).fill()
        NSGraphicsContext.restoreGraphicsState()

        Gauge.text(text as String,
                   in: badge.insetBy(dx: diameter * 0.10, dy: diameter * 0.30),
                   weight: .bold, color: .white, maximumSize: diameter * 0.60)
    }
}

@objc(FolderDockTilePlugin)
final class FolderDockTilePlugin: TilePlugin {
    private var folderView: FolderTileView? { tileView as? FolderTileView }
    private var monitor: FolderMonitor { FolderMonitor.shared(instanceID) }
    private var token: UUID?
    private var lastToken = ""

    override func makeTileView() -> TileView {
        FolderTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func didAttach() {
        token = monitor.addListener { [weak self] in
            guard let self, let view = self.folderView else { return }
            let current = view.renderToken
            guard current != self.lastToken else { return }
            self.lastToken = current
            self.refresh()
        }
    }

    override func willDetach() {
        if let token { monitor.removeListener(token) }
        token = nil
    }

}
