import AppKit

/// The contents of one folder, as rows: icon, name, and whatever the sort makes
/// worth showing on the right. Clicking a folder goes into it; clicking
/// anything else opens it.
final class FolderListView: NSView {
    var onOpen: ((FolderEntry) -> Void)?
    var onEnter: ((FolderEntry) -> Void)?
    var onReveal: ((FolderEntry) -> Void)?
    var onGrantAccess: (() -> Void)?
    /// Set while something is being dropped: only folders are listed, and each
    /// one carries the button that copies into it.
    var onCopyInto: ((FolderEntry) -> Void)?
    var isDropping = false

    private(set) var reading: FolderReading = .loading
    private var entries: [FolderEntry] = []
    private var hovered = -1 {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    /// The one button this view can have, when there is nothing to list.
    private var actionRect: NSRect = .zero

    static let rowHeight: CGFloat = 30

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ reading: FolderReading) {
        self.reading = reading
        entries = {
            guard case let .items(found) = reading else { return [] }
            // Dropping into a file is not a thing: only the folders are offered.
            return isDropping ? found.filter(\.isDirectory) : found
        }()
        hovered = -1
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// How tall the rows want to be, so the sheet can decide whether to scroll.
    var contentHeight: CGFloat {
        entries.isEmpty ? 64 : CGFloat(entries.count) * Self.rowHeight + 6
    }

    /// Where the copy-here button sits on a row.
    private func plusRect(in row: NSRect) -> NSRect {
        NSRect(x: row.maxX - 30, y: row.midY - 9, width: 18, height: 18)
    }

    private func rect(of index: Int) -> NSRect {
        NSRect(x: 0, y: 3 + CGFloat(index) * Self.rowHeight,
               width: bounds.width, height: Self.rowHeight)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !entries.isEmpty else {
            drawMessage()
            return
        }
        actionRect = .zero
        for index in entries.indices {
            let row = rect(of: index)
            guard row.intersects(dirtyRect) else { continue }
            draw(entries[index], in: row, hovered: hovered == index)
        }
    }

    private func draw(_ entry: FolderEntry, in row: NSRect, hovered: Bool) {
        if hovered {
            NSColor(calibratedWhite: 1, alpha: 0.14).setFill()
            NSBezierPath(roundedRect: row.insetBy(dx: 4, dy: 1),
                         xRadius: 7, yRadius: 7).fill()
        }

        let side: CGFloat = 19
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        // Sized before drawing, or a 32-point representation is stretched over
        // a Retina row and looks it.
        icon.size = NSSize(width: side, height: side)
        icon.draw(in: NSRect(x: row.minX + 10, y: row.midY - side / 2,
                             width: side, height: side),
                  from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

        // The detail on the right is measured first: the name gets what is left.
        let detail = entry.detail(for: sort)
        let detailWidth = min(width(of: detail, size: 10.5, weight: .regular) + 2, 130)
        let chevron: CGFloat = entry.isDirectory ? 14 : 0
        let nameBox = NSRect(x: row.minX + 37, y: row.minY,
                             width: max(row.width - 37 - detailWidth - chevron - 16, 20),
                             height: row.height)
        draw(entry.name, in: nameBox, size: 12.5, weight: .regular,
             colour: .labelColor, alignment: .left)
        draw(detail, in: NSRect(x: nameBox.maxX + 6, y: row.minY,
                                width: detailWidth, height: row.height),
             size: 10.5, weight: .regular, colour: .secondaryLabelColor, alignment: .right)

        guard entry.isDirectory else { return }
        guard isDropping else {
            Gauge.symbol("chevron.right",
                         in: NSRect(x: row.maxX - 22, y: row.midY - 5, width: 10, height: 10),
                         color: .tertiaryLabelColor)
            return
        }
        // The plus copies here; the rest of the row still goes deeper.
        let chip = plusRect(in: row)
        NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: chip).fill()
        Gauge.symbol("plus", in: chip.insetBy(dx: 5, dy: 5), color: .white)
    }

    /// What is shown when there are no rows: why, and what can be done.
    private func drawMessage() {
        let (text, action): (String, String?) = {
            switch reading {
            case .loading: return (T("Sto leggendo…", "Reading…"), nil)
            case .items: return (T("Cartella vuota", "The folder is empty"), nil)
            case .denied: return (T("macOS non mi lascia leggere questa cartella.",
                                    "macOS will not let this folder be read."),
                                  T("Consenti l'accesso…", "Allow access…"))
            case .missing: return (T("La cartella non c'è più.", "The folder is gone."), nil)
            case let .failed(why): return (why, nil)
            }
        }()

        let box = NSRect(x: 12, y: 8, width: bounds.width - 24, height: 34)
        draw(text, in: box, size: 12, weight: .medium, colour: .secondaryLabelColor,
             alignment: .center)

        guard let action else {
            actionRect = .zero
            return
        }
        let width = min(self.width(of: action, size: 12, weight: .semibold) + 26,
                        bounds.width - 40)
        actionRect = NSRect(x: bounds.midX - width / 2, y: box.maxY + 2,
                            width: width, height: 26)
        NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: actionRect, xRadius: 13, yRadius: 13).fill()
        draw(action, in: actionRect, size: 12, weight: .semibold, colour: .white,
             alignment: .center)
    }

    var sort: FolderSort = .dateAdded

    // MARK: Text

    private func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
        ]).width
    }

    private func draw(_ text: String, in rect: NSRect, size: CGFloat,
                      weight: NSFont.Weight, colour: NSColor,
                      alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingMiddle
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let height = font.ascender - font.descender
        (text as NSString).draw(
            in: NSRect(x: rect.minX, y: rect.midY - height / 2,
                       width: rect.width, height: height),
            withAttributes: [.font: font, .foregroundColor: colour,
                             .paragraphStyle: paragraph])
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hovered = entries.indices.first { rect(of: $0).contains(point) } ?? -1
    }

    override func mouseExited(with event: NSEvent) { hovered = -1 }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !actionRect.isEmpty, actionRect.contains(point) {
            onGrantAccess?()
            return
        }
        guard let index = entries.indices.first(where: { rect(of: $0).contains(point) })
        else { return }
        let entry = entries[index]
        if isDropping, entry.isDirectory,
           plusRect(in: rect(of: index)).insetBy(dx: -5, dy: -5).contains(point) {
            onCopyInto?(entry)
            return
        }
        // Held down, a folder opens instead of being walked into — the short
        // way out when the list is not where you wanted to end up.
        if entry.isDirectory, event.modifierFlags.contains(.command) {
            onOpen?(entry)
            return
        }
        // Into a folder rather than opening it: the point of the list is to go
        // through the tree without leaving for the Finder.
        entry.isDirectory ? onEnter?(entry) : onOpen?(entry)
    }

    /// A menu of our own, which works: this one is shown by our process, not
    /// handed to the Dock.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = entries.indices.first(where: { rect(of: $0).contains(point) })
        else { return }
        let entry = entries[index]

        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = NSMenuItem(title: entry.isDirectory
            ? T("Apri nel Finder", "Open in the Finder")
            : T("Apri", "Open"), action: #selector(chooseOpen), keyEquivalent: "")
        open.target = self
        open.representedObject = entry.url
        menu.addItem(open)

        if entry.isDirectory {
            let enter = NSMenuItem(title: T("Entra", "Go into it"),
                                   action: #selector(chooseEnter), keyEquivalent: "")
            enter.target = self
            enter.representedObject = entry.url
            menu.addItem(enter)
        }

        menu.addItem(.separator())
        let reveal = NSMenuItem(title: T("Mostra nel Finder", "Show in the Finder"),
                                action: #selector(chooseReveal), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry.url
        menu.addItem(reveal)

        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func entry(for sender: NSMenuItem) -> FolderEntry? {
        guard let url = sender.representedObject as? URL else { return nil }
        return entries.first { $0.url == url }
    }

    @objc private func chooseOpen(_ sender: NSMenuItem) {
        entry(for: sender).map { onOpen?($0) }
    }

    @objc private func chooseEnter(_ sender: NSMenuItem) {
        entry(for: sender).map { onEnter?($0) }
    }

    @objc private func chooseReveal(_ sender: NSMenuItem) {
        entry(for: sender).map { onReveal?($0) }
    }
}
