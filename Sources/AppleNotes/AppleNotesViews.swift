import AppKit

/// Shared drawing: the widget is the same note in two shapes.
private enum NoteDrawing {
    static func lines(for note: AppleNote?, settings: AppleNotesSettings,
                      snapshot: AppleNotesBridge.Snapshot) -> (title: String, body: String) {
        if let failure = snapshot.failure, snapshot.notes.isEmpty {
            return (T("Note", "Notes"), failure)
        }
        guard let note else {
            return (T("Note", "Notes"), T("Nessuna nota", "No notes"))
        }
        return (note.title, settings.showsSnippet ? note.snippet : relative(note.modified))
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// The most recent note, as a square tile: a sticky with a title and the start
/// of what is written on it.
final class AppleNotesTileView: TileView {
    private lazy var settings = AppleNotesSettings.current(resolvedInstance("applenotes"))
    private var snapshot = AppleNotesBridge.read()
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observer = AppleNotesBridge.observe { [weak self] in
            self?.snapshot = AppleNotesBridge.read()
            self?.needsDisplay = true
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    override func reloadSettings() {
        settings = AppleNotesSettings.current(resolvedInstance("applenotes"))
        accent = settings.accent
        snapshot = AppleNotesBridge.read()
        needsDisplay = true
    }

    var latest: AppleNote? { snapshot.notes.first }

    var renderToken: String {
        "\(latest?.id ?? "—")|\(latest?.modified.timeIntervalSince1970 ?? 0)|\(settings.folder)"
    }

    override func draw(_ dirtyRect: NSRect) {
        guard settings.mode == .tile else { return }
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        // A band of the accent along the top, like the ruled line on a pad.
        NSGraphicsContext.saveGraphicsState()
        TileGeometry.cardPath(in: card).addClip()
        palette.accent.setFill()
        NSRect(x: card.minX, y: card.maxY - side * 0.10, width: card.width, height: side * 0.10).fill()
        NSGraphicsContext.restoreGraphicsState()

        let text = NoteDrawing.lines(for: latest, settings: settings, snapshot: snapshot)
        let inset = side * 0.10

        let titleBox = NSRect(x: card.minX + inset, y: card.midY - side * 0.02,
                              width: card.width - inset * 2, height: side * 0.30)
        draw(text.title, in: titleBox, size: side * 0.15, weight: .semibold,
             color: palette.primary, lines: 2)

        guard !text.body.isEmpty else { return }
        let bodyBox = NSRect(x: card.minX + inset, y: card.minY + inset * 0.6,
                             width: card.width - inset * 2, height: side * 0.30)
        draw(text.body, in: bodyBox, size: side * 0.105, weight: .regular,
             color: palette.secondary, lines: 3)
    }

    private func draw(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight,
                      color: NSColor, lines: Int) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }
}

/// The same note, wide: room for the title, a line of what it says, and a
/// button that starts a new one.
final class AppleNotesBarView: BarContentView {
    var onOpen: ((AppleNote?) -> Void)?
    var onCreate: (() -> Void)?

    private lazy var settings = AppleNotesSettings.current(resolvedInstance("applenotes"))
    private var snapshot = AppleNotesBridge.read()
    private var observer: NSObjectProtocol?
    private var hovered: Int?
    private var pressed: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observer = AppleNotesBridge.observe { [weak self] in
            self?.snapshot = AppleNotesBridge.read()
            self?.needsDisplay = true
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    override func reloadSettings() {
        settings = AppleNotesSettings.current(resolvedInstance("applenotes"))
        snapshot = AppleNotesBridge.read()
        needsDisplay = true
    }

    private var latest: AppleNote? { snapshot.notes.first }

    private var newButton: NSRect {
        let plate = contentPlate
        let side = controlSide
        return NSRect(x: plate.maxX - side, y: plate.midY - side / 2, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWidgetBackground()
        let plate = contentPlate
        let palette = TilePalette.resolve(dark: isDarkContext,
                                          accent: settings.accent)

        let stripe = NSRect(x: plate.minX, y: plate.minY + plate.height * 0.18,
                            width: plate.height * 0.06, height: plate.height * 0.64)
        palette.accent.setFill()
        NSBezierPath(roundedRect: stripe, xRadius: stripe.width / 2, yRadius: stripe.width / 2).fill()

        let text = NoteDrawing.lines(for: latest, settings: settings, snapshot: snapshot)
        let textX = stripe.maxX + plate.height * 0.16
        let textWidth = max(0, newButton.minX - textX - plate.height * 0.12)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        (text.title as NSString).draw(
            in: NSRect(x: textX, y: plate.midY - plate.height * 0.02,
                       width: textWidth, height: plate.height * 0.40),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: plate.height * 0.27, weight: .semibold),
                .foregroundColor: palette.primary,
                .paragraphStyle: paragraph,
            ])
        (text.body as NSString).draw(
            in: NSRect(x: textX, y: plate.minY + plate.height * 0.16,
                       width: textWidth, height: plate.height * 0.30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: plate.height * 0.21, weight: .regular),
                .foregroundColor: palette.secondary,
                .paragraphStyle: paragraph,
            ])

        let button = newButton
        if hovered == 1 || pressed == 1 {
            NSColor(calibratedWhite: isDarkContext ? 1 : 0,
                    alpha: pressed == 1 ? 0.20 : 0.12).setFill()
            NSBezierPath(ovalIn: button).fill()
        }
        Gauge.symbol("square.and.pencil",
                     in: button.insetBy(dx: button.width * 0.26, dy: button.height * 0.26),
                     color: palette.primary)
    }

    // MARK: Interaction

    private func target(at point: NSPoint) -> Int? {
        if newButton.insetBy(dx: -3, dy: -3).contains(point) { return 1 }
        return contentPlate.contains(point) ? 0 : nil
    }

    override func mouseDown(with event: NSEvent) {
        pressed = target(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let hit = target(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil; needsDisplay = true }
        guard let pressed, hit == pressed else { return }
        pressed == 1 ? onCreate?() : onOpen?(latest)
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = target(at: convert(event.locationInWindow, from: nil))
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
}

@objc(AppleNotesDockTilePlugin)
final class AppleNotesDockTilePlugin: TilePlugin {
    private var notesView: AppleNotesTileView? { tileView as? AppleNotesTileView }
    private var observer: NSObjectProtocol?
    private var lastToken = ""

    override func makeTileView() -> TileView {
        AppleNotesTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    /// Notes is asked once a minute, and only by whoever is allowed to ask.
    override var tickInterval: TimeInterval { 60 }

    override func didAttach() {
        observer = AppleNotesBridge.observe { [weak self] in
            guard let self, let view = self.notesView else { return }
            let current = view.renderToken
            guard current != self.lastToken else { return }
            self.lastToken = current
            self.refresh()
        }
        tick()
    }

    override func willDetach() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    override func tick() {
        AppleNotesBridge.refresh(folder: AppleNotesSettings.current(instanceID).folder)
    }

    override func customMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let create = NSMenuItem(title: T("Nuova nota", "New note"),
                                action: #selector(createNote), keyEquivalent: "")
        create.target = self
        items.append(create)

        let open = NSMenuItem(title: T("Apri Note", "Open Notes"),
                              action: #selector(openApp), keyEquivalent: "")
        open.target = self
        items.append(open)
        items.append(.separator())

        let snapshot = AppleNotesBridge.read()
        for note in snapshot.notes.prefix(8) {
            let item = NSMenuItem(title: note.title, action: #selector(openNote(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = note.id
            items.append(item)
        }
        if snapshot.notes.isEmpty {
            let empty = NSMenuItem(title: snapshot.failure ?? T("Nessuna nota", "No notes"),
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            items.append(empty)
        }
        return items
    }

    @objc private func createNote() {
        AppleNotesBridge.createNote(in: AppleNotesSettings.current(instanceID).folder)
    }

    @objc private func openApp() {
        AppleNotesBridge.openApp()
    }

    @objc private func openNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppleNotesBridge.open(AppleNote(id: id, title: "", folder: "", modified: Date(), snippet: ""))
    }
}
