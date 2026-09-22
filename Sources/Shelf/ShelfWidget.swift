import AppKit

struct ShelfSettings: Equatable {
    /// Beyond this the oldest is dropped: a shelf that never forgets is a
    /// folder, and there is already a widget for those.
    static let capacity = 12

    /// Paths, most recent first. The files stay where they are — the shelf
    /// holds a pointer, not a copy.
    var paths: [String] = []
    var accentHex = "#0A84FF"

    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }
    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static func paths(_ instance: String) -> String { "\(instance).paths" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: ShelfSettings { current("shelf") }

    static func current(_ instance: String) -> ShelfSettings {
        let store = SettingsStore.shared
        let defaults = ShelfSettings()
        let stored = store.strings(Key.paths(instance)) ?? []
        return ShelfSettings(
            // Anything that has been moved or thrown away quietly leaves.
            paths: stored.filter { FileManager.default.fileExists(atPath: $0) },
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "shelf") {
        SettingsStore.shared.set([
            Key.paths(instance): paths,
            Key.accent(instance): accentHex,
        ])
    }

    /// Adds files to the front, without repeating what is already there.
    static func add(_ urls: [URL], to instance: String) {
        var settings = current(instance)
        let incoming = urls.map(\.path)
        settings.paths = (incoming + settings.paths.filter { !incoming.contains($0) })
        settings.paths = Array(settings.paths.prefix(capacity))
        settings.save(instance)
    }
}

/// A place to put a file down for a minute.
///
/// The files are not moved or copied: the shelf keeps where they are, so
/// taking one out is a drag like any other and leaving it there costs nothing.
final class ShelfBarView: BarContentView {
    var onOpen: ((URL) -> Void)?

    private lazy var settings = ShelfSettings.current(resolvedInstance("shelf"))
    private var hovered: Int?
    private var pressed: Int?
    private var dragOrigin: NSPoint?
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        observer = SettingsStore.shared.observeChanges { [weak self] in
            self?.reloadSettings()
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    override func reloadSettings() {
        settings = ShelfSettings.current(resolvedInstance("shelf"))
        needsDisplay = true
    }

    private var isDropTarget = false {
        didSet { if isDropTarget != oldValue { needsDisplay = true } }
    }

    // MARK: Layout

    /// Two rows of files where the notch gave two caselle: the difference
    /// between putting one thing down and putting down what you are working on.
    private var rowsOfFiles: Int { fillsHeight && verticalSlots >= 2 ? 2 : 1 }

    private func slots() -> [NSRect] {
        let plate = contentPlate
        let rows = rowsOfFiles
        let gap = controlGap * 0.8
        let rowHeight = (plate.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let side = min(rowHeight, controlSide * 1.2)
        let perRow = max(Int((plate.width + gap) / (side + gap)), 1)
        return (0..<(perRow * rows)).map { index in
            let column = index % perRow
            let row = index / perRow
            return NSRect(x: plate.minX + CGFloat(column) * (side + gap),
                          y: plate.maxY - CGFloat(row + 1) * rowHeight
                              - CGFloat(row) * gap + (rowHeight - side) / 2,
                          width: side, height: side)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        let palette = TilePalette.resolve(dark: isDarkContext, accent: settings.accent)
        let boxes = slots()
        let urls = settings.urls

        if isDropTarget {
            let plate = contentPlate
            let path = NSBezierPath(roundedRect: plate,
                                    xRadius: plate.height * TileGeometry.cornerRatio,
                                    yRadius: plate.height * TileGeometry.cornerRatio)
            palette.accent.withAlphaComponent(0.22).setFill()
            path.fill()
        }

        guard !urls.isEmpty else {
            let plate = contentPlate
            Gauge.text(T("Trascina qui i file", "Drop files here"),
                       in: plate, weight: .medium, color: palette.secondary,
                       maximumSize: plate.height * 0.30)
            return
        }

        for (index, box) in boxes.enumerated() {
            guard index < urls.count else { break }
            if hovered == index || pressed == index {
                NSColor(calibratedWhite: isDarkContext ? 1 : 0,
                        alpha: pressed == index ? 0.20 : 0.12).setFill()
                NSBezierPath(roundedRect: box.insetBy(dx: -2, dy: -2),
                             xRadius: box.width * 0.24, yRadius: box.width * 0.24).fill()
            }
            let icon = NSWorkspace.shared.icon(forFile: urls[index].path)
            icon.size = box.size
            icon.draw(in: box.insetBy(dx: box.width * 0.08, dy: box.height * 0.08),
                      from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }

        // What did not fit is counted rather than hidden.
        let overflow = urls.count - boxes.count
        guard overflow > 0, let last = boxes.last else { return }
        Gauge.text("+\(overflow)",
                   in: NSRect(x: last.maxX, y: last.minY, width: contentPlate.maxX - last.maxX,
                              height: last.height),
                   weight: .semibold, color: palette.secondary, maximumSize: last.height * 0.42)
    }

    // MARK: Pointer

    private func index(at point: NSPoint) -> Int? {
        guard let hit = slots().firstIndex(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }),
              hit < settings.urls.count else { return nil }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = index(at: point)
        dragOrigin = point
        needsDisplay = true
    }

    /// Far enough and it is a drag, not a click: the file leaves the shelf the
    /// same way it would leave a Finder window.
    override func mouseDragged(with event: NSEvent) {
        guard let pressed, let dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) > 6 else { return }
        guard pressed < settings.urls.count else { return }

        let url = settings.urls[pressed]
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let box = slots()[pressed]
        item.setDraggingFrame(box, contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)

        self.pressed = nil
        self.dragOrigin = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { pressed = nil; dragOrigin = nil; needsDisplay = true }
        guard let pressed, index(at: point) == pressed, pressed < settings.urls.count else { return }
        onOpen?(settings.urls[pressed])
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = index(at: convert(event.locationInWindow, from: nil))
        if hit != hovered { hovered = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if let hit = index(at: point) {
            removing = settings.urls[hit]
            for (title, action) in [(T("Apri", "Open"), #selector(openItem)),
                                    (T("Mostra nel Finder", "Show in Finder"), #selector(revealItem)),
                                    (T("Togli dalla mensola", "Take off the shelf"), #selector(removeItem))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let clear = NSMenuItem(title: T("Svuota la mensola", "Empty the shelf"),
                               action: #selector(clearShelf), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private var removing: URL?

    @objc private func openItem() {
        removing.map { NSWorkspace.shared.open($0) }
    }

    @objc private func revealItem() {
        removing.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    }

    @objc private func removeItem() {
        guard let removing else { return }
        var updated = settings
        updated.paths.removeAll { $0 == removing.path }
        updated.save(resolvedInstance("shelf"))
        reloadSettings()
    }

    @objc private func clearShelf() {
        var updated = settings
        updated.paths = []
        updated.save(resolvedInstance("shelf"))
        reloadSettings()
    }

    // MARK: Dropping

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else { return false }
        ShelfSettings.add(urls, to: resolvedInstance("shelf"))
        reloadSettings()
        return true
    }
}

extension ShelfBarView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy, not move: taking a file off the shelf must not take it from
        // wherever it actually lives.
        .copy
    }
}
