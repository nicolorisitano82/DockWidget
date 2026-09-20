import AppKit

/// One volume filling a square tile: a ring of used space, the name, and how
/// much is left.
final class DisksTileView: TileView {
    private var settings = DisksSettings.current
    private var token: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        subscribe()
    }

    deinit {
        if let token { VolumeScanner.shared.removeListener(token) }
    }

    override func reloadSettings() {
        settings = DisksSettings.current
        accent = settings.accent
        needsDisplay = true
    }

    private func subscribe() {
        token = VolumeScanner.shared.addListener { [weak self] in self?.needsDisplay = true }
    }

    var volume: VolumeInfo? {
        settings.tileVolume.isEmpty
            ? VolumeScanner.shared.volumes.first
            : VolumeScanner.shared.volume(named: settings.tileVolume)
    }

    var renderToken: String {
        guard let volume else { return "—" }
        return "\(volume.name)|\(Int(volume.fraction * 1000))"
    }

    override func draw(_ dirtyRect: NSRect) {
        guard settings.mode == .tile else { return }
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        guard let volume else {
            Gauge.text(T("Nessun volume", "No volume"),
                       in: card, weight: .medium, color: palette.secondary, maximumSize: side * 0.13)
            return
        }

        Gauge.ring(in: card.insetBy(dx: side * 0.14, dy: side * 0.14), fraction: volume.fraction,
                   width: side * 0.085, color: palette.accent, track: Gauge.trackColor())
        Gauge.symbol(volume.symbol,
                     in: NSRect(x: card.midX - side * 0.11, y: card.midY + side * 0.12,
                                width: side * 0.22, height: side * 0.16),
                     color: palette.secondary)
        Gauge.text(SensorFormat.percent(volume.fraction),
                   in: NSRect(x: card.minX + side * 0.16, y: card.midY - side * 0.12,
                              width: card.width - side * 0.32, height: side * 0.24),
                   weight: .semibold, color: palette.primary, maximumSize: side * 0.26)

        let caption = settings.showsFree
            ? T("\(SensorFormat.bytes(Double(volume.free))) liberi",
                "\(SensorFormat.bytes(Double(volume.free))) free")
            : volume.name
        Gauge.text(caption,
                   in: NSRect(x: card.minX + side * 0.10, y: card.minY + side * 0.09,
                              width: card.width - side * 0.20, height: side * 0.15),
                   weight: .medium, color: palette.secondary, maximumSize: side * 0.11)
    }
}

/// Every mounted volume, one Dock tile each.
final class DisksBarView: BarContentView {
    private var settings = DisksSettings.current
    private var token: UUID?
    private var hovered: Int? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        token = VolumeScanner.shared.addListener { [weak self] in self?.needsDisplay = true }
    }

    deinit {
        if let token { VolumeScanner.shared.removeListener(token) }
    }

    override func reloadSettings() {
        settings = DisksSettings.current
        needsDisplay = true
    }

    /// As many volumes as there are tiles. More than that and the last cell
    /// counts the ones that did not fit, because a bar cannot grow by itself:
    /// widening it restarts the Dock, and a drive being plugged in is not
    /// worth that.
    private var shown: [VolumeInfo] {
        Array(VolumeScanner.shared.volumes.prefix(tileCount))
    }

    private var overflow: Int {
        max(VolumeScanner.shared.volumes.count - tileCount, 0)
    }

    /// A cell is always one Dock tile wide, whatever is mounted: a single
    /// volume in a three-tile bar should look like one disk with room beside
    /// it, not like one enormous disk.
    private func cells() -> [NSRect] {
        let plate = self.plate
        let width = plate.width / CGFloat(max(tileCount, 1))
        return (0..<max(tileCount, 1)).map {
            NSRect(x: plate.minX + CGFloat($0) * width, y: plate.minY,
                   width: width, height: plate.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let palette = TilePalette.resolve(dark: SystemAppearance.shared.isDark,
                                          accent: settings.accent)
        let volumes = shown
        for (index, rect) in cells().enumerated() {
            guard index < volumes.count else { break }
            let volume = volumes[index]
            let side = min(rect.width, rect.height) * (hovered == index ? 1.0 : 0.94)
            let box = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                             width: side, height: side)

            let isLast = index == volumes.count - 1 && overflow > 0
            Gauge.ring(in: box, fraction: volume.fraction, width: side * 0.11,
                       color: palette.accent, track: Gauge.trackColor())
            Gauge.symbol(volume.symbol,
                         in: NSRect(x: box.midX - side * 0.11, y: box.midY + side * 0.10,
                                    width: side * 0.22, height: side * 0.15),
                         color: palette.secondary)
            Gauge.text(isLast ? "+\(overflow)" : SensorFormat.percent(volume.fraction),
                       in: NSRect(x: box.minX + side * 0.16, y: box.midY - side * 0.20,
                                  width: box.width - side * 0.32, height: side * 0.28),
                       weight: .semibold, color: palette.primary, maximumSize: side * 0.30)
        }
    }

    // MARK: Interaction

    private func index(at point: NSPoint) -> Int? {
        cells().firstIndex { $0.contains(point) }
    }

    private func volume(at point: NSPoint) -> VolumeInfo? {
        guard let index = index(at: point) else { return nil }
        let volumes = shown
        return index < volumes.count ? volumes[index] : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let volume = volume(at: convert(event.locationInWindow, from: nil)) else { return }
        NSWorkspace.shared.open(volume.url)
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
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
        guard let volume = volume(at: convert(event.locationInWindow, from: nil)) else { return }
        ejecting = volume

        let menu = NSMenu()
        let title = NSMenuItem(title: "\(volume.name) — \(SensorFormat.bytes(Double(volume.free))) "
                               + T("liberi", "free"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let open = NSMenuItem(title: T("Apri nel Finder", "Open in Finder"),
                              action: #selector(openVolume), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        if !volume.isBoot, volume.isRemovable || !volume.isInternal {
            let eject = NSMenuItem(title: T("Espelli", "Eject"), action: #selector(ejectVolume),
                                   keyEquivalent: "")
            eject.target = self
            menu.addItem(eject)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private var ejecting: VolumeInfo?

    @objc private func openVolume() {
        guard let ejecting else { return }
        NSWorkspace.shared.open(ejecting.url)
    }

    @objc private func ejectVolume() {
        guard let ejecting else { return }
        VolumeScanner.shared.eject(ejecting)
    }
}

@objc(DisksDockTilePlugin)
final class DisksDockTilePlugin: TilePlugin {
    private var disksView: DisksTileView? { tileView as? DisksTileView }
    private var token: UUID?
    private var lastToken = ""

    override func makeTileView() -> TileView {
        DisksTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func didAttach() {
        token = VolumeScanner.shared.addListener { [weak self] in
            guard let self, let view = self.disksView else { return }
            let current = view.renderToken
            guard current != self.lastToken else { return }
            self.lastToken = current
            self.refresh()
        }
    }

    override func willDetach() {
        if let token { VolumeScanner.shared.removeListener(token) }
        token = nil
    }

    override func customMenuItems() -> [NSMenuItem] {
        VolumeScanner.shared.volumes.prefix(6).map { volume in
            let item = NSMenuItem(
                title: "\(volume.name) — \(SensorFormat.percent(volume.fraction))",
                action: nil, keyEquivalent: ""
            )
            item.isEnabled = false
            return item
        }
    }
}
