import AppKit

struct FolderSettings: Equatable {
    /// Empty means no folder chosen yet.
    var path: String = ""
    var showsCount = true
    var accentHex = "#0A84FF"

    var url: URL? { path.isEmpty ? nil : URL(fileURLWithPath: path) }
    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static let path = "folder.path"
        static let showsCount = "folder.showsCount"
        static let accent = "folder.accent"
    }

    static var current: FolderSettings {
        let store = SettingsStore.shared
        let defaults = FolderSettings()
        return FolderSettings(
            path: store.string(Key.path, or: defaults.path),
            showsCount: store.bool(Key.showsCount, or: defaults.showsCount),
            accentHex: store.string(Key.accent, or: defaults.accentHex)
        )
    }

    func save() {
        SettingsStore.shared.set([
            Key.path: path,
            Key.showsCount: showsCount,
            Key.accent: accentHex,
        ])
    }
}

/// Watches one folder and keeps a short list of what is in it.
///
/// A file descriptor source rather than a timer: the tile should change the
/// moment something lands in the folder, and stay quiet the rest of the day.
final class FolderMonitor {
    static let shared = FolderMonitor()

    private(set) var items: [URL] = []
    private(set) var count = 0

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var watched: String = ""
    private var listeners: [UUID: () -> Void] = [:]

    @discardableResult
    func addListener(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        watch(FolderSettings.current.path)
        handler()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty { stop() }
    }

    func watch(_ path: String) {
        guard path != watched || source == nil else { return }
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
        watched = ""
    }

    private func reload() {
        guard let url = FolderSettings.current.url else {
            items = []
            count = 0
            listeners.values.forEach { $0() }
            return
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Most recent first: what just landed is what you are looking for.
        items = contents.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return left > right
        }
        count = items.count
        listeners.values.forEach { $0() }
    }

    /// Moves dropped files into the watched folder.
    static func accept(_ files: [URL]) {
        guard let destination = FolderSettings.current.url else { return }
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: target)
        }
    }
}

/// The folder as a Dock tile: its own icon, a stack of what is inside, and a
/// count.
final class FolderTileView: TileView {
    private var settings = FolderSettings.current
    private var token: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        token = FolderMonitor.shared.addListener { [weak self] in self?.needsDisplay = true }
    }

    deinit {
        if let token { FolderMonitor.shared.removeListener(token) }
    }

    override func reloadSettings() {
        settings = FolderSettings.current
        accent = settings.accent
        FolderMonitor.shared.watch(settings.path)
        needsDisplay = true
    }

    var renderToken: String { "\(settings.path)|\(FolderMonitor.shared.count)" }

    override func draw(_ dirtyRect: NSRect) {
        let card = TileGeometry.artworkRect(in: bounds)
        let side = card.width
        let palette = self.palette

        guard let url = settings.url else {
            drawCard()
            Gauge.symbol("folder.badge.questionmark",
                         in: card.insetBy(dx: side * 0.3, dy: side * 0.3),
                         color: palette.secondary)
            return
        }

        // The Finder's own icon for this folder, so a coloured or custom folder
        // keeps looking like itself in the Dock.
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.draw(in: card, from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: nil)

        // The two most recent items peek out from behind it.
        let previews = FolderMonitor.shared.items.prefix(2)
        for (index, item) in previews.enumerated().reversed() {
            let size = side * 0.30
            let box = NSRect(x: card.midX - size / 2 + CGFloat(index) * size * 0.42,
                             y: card.maxY - size * (0.92 + CGFloat(index) * 0.10),
                             width: size, height: size)
            NSWorkspace.shared.icon(forFile: item.path)
                .draw(in: box, from: .zero, operation: .sourceOver,
                      fraction: index == 0 ? 1 : 0.75, respectFlipped: true, hints: nil)
        }

        guard settings.showsCount, FolderMonitor.shared.count > 0 else { return }
        let text = "\(FolderMonitor.shared.count)" as NSString
        let diameter = side * (text.length > 2 ? 0.40 : 0.34)
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

        Gauge.text(text as String, in: badge.insetBy(dx: diameter * 0.12, dy: diameter * 0.28),
                   weight: .bold, color: .white, maximumSize: diameter * 0.52)
    }
}

@objc(FolderDockTilePlugin)
final class FolderDockTilePlugin: TilePlugin {
    private var folderView: FolderTileView? { tileView as? FolderTileView }
    private var token: UUID?
    private var lastToken = ""

    override func makeTileView() -> TileView {
        FolderTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func didAttach() {
        token = FolderMonitor.shared.addListener { [weak self] in
            guard let self, let view = self.folderView else { return }
            let current = view.renderToken
            guard current != self.lastToken else { return }
            self.lastToken = current
            self.refresh()
        }
    }

    override func willDetach() {
        if let token { FolderMonitor.shared.removeListener(token) }
        token = nil
    }

    /// The menu is the folder: the most recent things in it, one click away.
    override func customMenuItems() -> [NSMenuItem] {
        guard let url = FolderSettings.current.url else { return [] }
        var items: [NSMenuItem] = []

        let open = NSMenuItem(title: T("Apri la cartella", "Open the folder"),
                              action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        items.append(open)
        items.append(.separator())

        for item in FolderMonitor.shared.items.prefix(8) {
            let entry = NSMenuItem(title: item.lastPathComponent, action: #selector(openItem(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = item
            let icon = NSWorkspace.shared.icon(forFile: item.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            items.append(entry)
        }
        if FolderMonitor.shared.items.isEmpty {
            let empty = NSMenuItem(title: T("Cartella vuota", "The folder is empty"),
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            items.append(empty)
        }
        _ = url
        return items
    }

    @objc private func openFolder() {
        guard let url = FolderSettings.current.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}
