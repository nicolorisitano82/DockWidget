import AppKit

/// The pane of glass above the Dock: where you are, what is in it, and the way
/// out to the Finder.
///
/// It is a small browser rather than a single look: clicking a folder goes into
/// it and the chevron comes back to leave. The sort is remembered for the
/// widget, so a folder you keep by date stays by date.
final class FolderSheet: NSVisualEffectView {
    var onOpenItem: ((URL) -> Void)?
    var onOpenFolder: ((URL) -> Void)?
    var onHeightChange: (() -> Void)?

    private let instance: String
    private let root: URL
    private var levels: [URL]
    private var settings: FolderSettings

    private let list = FolderListView()
    private let scroll = NSScrollView()
    private let back = NSButton()
    private let title = NSTextField(labelWithString: "")
    private let sortButton = NSPopUpButton()
    private let open = NSButton()

    private static let header: CGFloat = 34
    private static let footer: CGFloat = 38
    private static let padding: CGFloat = 8
    /// The room the sheet is allowed to take, set when it is placed.
    private var ceiling: CGFloat = 400

    /// What is being dropped, when something is.
    private let dropping: [URL]

    init(instance: String, folder: URL, dropping: [URL] = []) {
        self.instance = instance
        self.dropping = dropping
        root = folder
        levels = [folder]
        settings = FolderSettings.current(instance)
        super.init(frame: .zero)

        // Glass rather than a painted card: the same material the system's own
        // floating panels are made of.
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor

        back.isBordered = false
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        back.imagePosition = .imageOnly
        back.target = self
        back.action = #selector(goBack)
        addSubview(back)

        title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        addSubview(title)

        sortButton.isBordered = false
        sortButton.pullsDown = true
        sortButton.imagePosition = .imageOnly
        sortButton.menu = makeSortMenu()
        addSubview(sortButton)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = list
        addSubview(scroll)

        open.isBordered = false
        open.wantsLayer = true
        open.target = self
        open.action = #selector(openCurrent)
        open.layer?.cornerRadius = 13
        open.layer?.backgroundColor = settings.accent.withAlphaComponent(0.92).cgColor
        addSubview(open)

        list.isDropping = !dropping.isEmpty
        list.onCopyInto = { [weak self] entry in self?.copy(into: entry.url) }
        list.onOpen = { [weak self] entry in self?.onOpenItem?(entry.url) }
        list.onEnter = { [weak self] entry in self?.enter(entry.url) }
        list.onReveal = { entry in
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
        list.onGrantAccess = { [weak self] in self?.grantAccess() }

        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("the preview is only ever built in code") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A click on the glass belongs to the glass, not to the screen behind it.
    override func mouseDown(with event: NSEvent) {}

    private var current: URL { levels.last ?? root }

    // MARK: Contents

    private func reload() {
        list.sort = settings.sort
        let reading = FolderReader.read(current, showsHidden: settings.showsHidden)
        if case let .items(found) = reading {
            list.show(.items(FolderReader.sorted(found, by: settings.sort,
                                                 reversed: settings.sortReversed)))
        } else {
            list.show(reading)
        }

        back.isHidden = levels.count < 2
        title.stringValue = dropping.isEmpty
            ? current.lastPathComponent
            : T("\(dropping.count) da copiare · \(current.lastPathComponent)",
                "\(dropping.count) to copy · \(current.lastPathComponent)")
        let name = current.lastPathComponent
        let title = dropping.isEmpty
            ? T("Apri \(name) nel Finder", "Open \(name) in the Finder")
            : T("Copia in «\(name)»", "Copy into “\(name)”")
        open.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: NSColor.white])
        sortButton.menu = makeSortMenu()
        onHeightChange?()
    }

    private func enter(_ folder: URL) {
        levels.append(folder)
        reload()
    }

    @objc private func goBack() {
        guard levels.count > 1 else { return }
        levels.removeLast()
        reload()
    }

    @objc private func openCurrent() {
        guard dropping.isEmpty else {
            copy(into: current)
            return
        }
        onOpenFolder?(current)
    }

    /// Copies what was dropped, then gets out of the way.
    private func copy(into folder: URL) {
        let done = FolderReader.copy(dropping, into: folder)
        Diagnostics.write("copiati \(done) di \(dropping.count) in \(folder.lastPathComponent)")
        onOpenFolder?(folder)
    }

    private func grantAccess() {
        FolderReader.requestAccess(to: current) { [weak self] granted in
            guard granted else { return }
            self?.reload()
        }
    }

    // MARK: Sorting

    private func makeSortMenu() -> NSMenu {
        let menu = NSMenu()
        // A pull-down's first item is its own face, never chosen.
        let face = NSMenuItem()
        face.image = NSImage(systemSymbolName: "arrow.up.arrow.down",
                             accessibilityDescription: T("Ordina", "Sort"))
        menu.addItem(face)

        for choice in FolderSort.allCases {
            let item = NSMenuItem(title: choice.label, action: #selector(pickSort(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == settings.sort ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let reversed = NSMenuItem(title: T("Ordine inverso", "Reverse order"),
                                  action: #selector(toggleReversed), keyEquivalent: "")
        reversed.target = self
        reversed.state = settings.sortReversed ? .on : .off
        menu.addItem(reversed)

        let hidden = NSMenuItem(title: T("Mostra i file nascosti", "Show hidden files"),
                                action: #selector(toggleHidden), keyEquivalent: "")
        hidden.target = self
        hidden.state = settings.showsHidden ? .on : .off
        menu.addItem(hidden)
        return menu
    }

    @objc private func pickSort(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = FolderSort(rawValue: raw) else { return }
        settings.sort = choice
        settings.save(instance)
        reload()
    }

    @objc private func toggleReversed() {
        settings.sortReversed.toggle()
        settings.save(instance)
        reload()
    }

    @objc private func toggleHidden() {
        settings.showsHidden.toggle()
        settings.save(instance)
        reload()
    }

    // MARK: Placing

    /// Above the tile, as wide as it was asked to be and no taller than the
    /// room between the Dock and the menu bar.
    func place(above tile: NSRect, within bounds: NSRect, ceiling: CGFloat) {
        self.ceiling = ceiling
        let width: CGFloat = 320
        var x = tile.midX - width / 2
        x = min(max(x, 12), bounds.maxX - width - 12)
        let room = max(ceiling - tile.maxY - 18, 200)
        let wanted = Self.header + list.contentHeight + Self.footer
        let height = min(wanted, room)
        frame = NSRect(x: x, y: tile.maxY + 12, width: width, height: height)
        layoutPieces()
    }

    private func layoutPieces() {
        let padding = Self.padding
        let width = bounds.width

        open.frame = NSRect(x: padding, y: padding,
                            width: width - padding * 2, height: Self.footer - padding * 2 + 4)

        let headerY = bounds.maxY - Self.header
        back.frame = NSRect(x: padding, y: headerY + 6, width: 22, height: 22)
        sortButton.frame = NSRect(x: width - padding - 26, y: headerY + 5, width: 26, height: 24)
        let titleX = back.isHidden ? padding + 4 : back.frame.maxX + 4
        title.frame = NSRect(x: titleX, y: headerY + 8,
                             width: max(sortButton.frame.minX - titleX - 6, 20), height: 18)

        scroll.frame = NSRect(x: 0, y: open.frame.maxY + 6,
                              width: width, height: max(headerY - open.frame.maxY - 6, 20))
        list.frame = NSRect(x: 0, y: 0, width: width,
                            height: max(list.contentHeight, scroll.frame.height))
    }

    /// Re-measures after the contents changed under it — going into a folder
    /// with three things in it should not leave a sheet sized for thirty.
    func remeasure(above tile: NSRect, within bounds: NSRect) {
        place(above: tile, within: bounds, ceiling: ceiling)
    }

    /// Fades up rather than appearing: a panel that arrives instantly reads as
    /// a glitch.
    func appear() {
        alphaValue = 0
        let target = frame
        frame = target.offsetBy(dx: 0, dy: -10)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().frame = target
        }
    }
}
