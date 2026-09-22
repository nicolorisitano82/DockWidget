import AppKit

final class FolderPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private var monitor: FolderMonitor { FolderMonitor.shared(instance) }
    private lazy var settings = FolderSettings.current(instance)
    private var pathLabel: NSTextField?
    private var placeRows: [NSView] = []
    private var clickRows: [NSView] = []
    private var token: UUID?

    override func makeTileView() -> TileView {
        FolderTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func refreshTick() -> Bool { false }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard token == nil else { return }
        token = monitor.addListener { [weak self] in
            self?.updateLabel()
            self?.reloadTile()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let token { monitor.removeListener(token) }
        token = nil
    }

    override func buildControls(in stack: NSStackView) {
        let choose = NSButton(title: T("Scegli la cartella…", "Choose the folder…"),
                              target: self, action: #selector(chooseFolder))
        stack.addArrangedSubview(labeled(T("Cartella", "Folder"), choose))

        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 392
        pathLabel = label
        stack.addArrangedSubview(label)

        stack.addArrangedSubview(checkbox(T("Mostra il conteggio", "Show the count"),
                                          isOn: settings.showsCount,
                                          action: #selector(countChanged)))

        stack.addArrangedSubview(sectionTitle(T("Nel Dock", "In the Dock")))

        let place = NSPopUpButton()
        for choice in FolderSettings.Place.allCases { place.addItem(withTitle: choice.label) }
        place.selectItem(at: FolderSettings.Place.allCases.firstIndex(of: settings.place) ?? 0)
        place.target = self
        place.action = #selector(placeChanged)
        stack.addArrangedSubview(labeled(T("Come sta", "How it sits"), place))

        let view = NSPopUpButton()
        for choice in FolderStack.View.allCases { view.addItem(withTitle: choice.label) }
        view.selectItem(at: FolderStack.View.allCases.firstIndex(of: settings.stackView) ?? 0)
        view.target = self
        view.action = #selector(stackViewChanged)
        placeRows.append(labeled(T("Apri come", "Open as"), view))

        let sort = NSPopUpButton()
        for choice in FolderStack.Sort.allCases { sort.addItem(withTitle: choice.label) }
        sort.selectItem(at: FolderStack.Sort.allCases.firstIndex(of: settings.stackSort) ?? 0)
        sort.target = self
        sort.action = #selector(stackSortChanged)
        placeRows.append(labeled(T("Ordina per", "Sort by"), sort))

        let display = NSPopUpButton()
        for choice in FolderStack.Display.allCases { display.addItem(withTitle: choice.label) }
        display.selectItem(at: FolderStack.Display.allCases.firstIndex(of: settings.stackDisplay) ?? 0)
        display.target = self
        display.action = #selector(stackDisplayChanged)
        placeRows.append(labeled(T("Mostra come", "Show as"), display))

        placeRows.forEach(stack.addArrangedSubview)

        let stackHint = NSTextField(wrappingLabelWithString: T(
            "Come pila è il Dock stesso a tenerla: il ventaglio, la griglia e l'elenco sono i suoi, con la loro animazione. In cambio la tile non è più nostra — niente conteggio, niente colore, niente anteprima.",
            "As a stack the Dock itself holds it: the fan, the grid and the list are its own, with their animation. In exchange the tile is no longer ours — no count, no colour, no preview."))
        stackHint.font = .systemFont(ofSize: 11)
        stackHint.textColor = .tertiaryLabelColor
        stackHint.preferredMaxLayoutWidth = 392
        placeRows.append(stackHint)
        stack.addArrangedSubview(stackHint)

        let clickTitle = sectionTitle(T("Il click sulla tile", "Clicking the tile"))
        clickRows.append(clickTitle)
        stack.addArrangedSubview(clickTitle)

        let click = NSPopUpButton()
        for choice in FolderSettings.Click.allCases { click.addItem(withTitle: choice.label) }
        click.selectItem(at: FolderSettings.Click.allCases.firstIndex(of: settings.click) ?? 0)
        click.target = self
        click.action = #selector(clickChanged)
        let clickRow = labeled(T("Cosa fa", "What it does"), click)
        clickRows.append(clickRow)
        stack.addArrangedSubview(clickRow)

        let previewHint = NSTextField(wrappingLabelWithString: T(
            "L'anteprima è un piccolo sfoglia-cartelle: ci entri dentro, la ordini, e da lì passi al Finder. La disegna l'agente della barra, quindi vuole il permesso di Accessibilità; senza, il click apre la cartella e basta.",
            "The preview is a small folder browser: you can go into subfolders, sort them, and move on to the Finder from there. It is drawn by the bar agent, so it wants the Accessibility permission; without it, a click just opens the folder."))
        previewHint.font = .systemFont(ofSize: 11)
        previewHint.textColor = .tertiaryLabelColor
        previewHint.preferredMaxLayoutWidth = 392
        clickRows.append(previewHint)
        stack.addArrangedSubview(previewHint)

        updatePreviewRows()

        let tint = NSPopUpButton()
        for entry in FolderTints.all {
            let item = NSMenuItem(title: entry.label, action: nil, keyEquivalent: "")
            item.image = FolderTints.swatch(entry.hex)
            tint.menu?.addItem(item)
        }
        tint.selectItem(at: FolderTints.all.firstIndex { $0.hex == settings.tintHex } ?? 0)
        tint.target = self
        tint.action = #selector(tintChanged)
        stack.addArrangedSubview(labeled(T("Colore cartella", "Folder colour"), tint))

        let symbol = NSPopUpButton()
        symbol.addItem(withTitle: T("Nessuno", "None"))
        for name in ActionSymbols.all {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            symbol.menu?.addItem(item)
        }
        symbol.selectItem(withTitle: settings.symbol.isEmpty ? T("Nessuno", "None") : settings.symbol)
        symbol.target = self
        symbol.action = #selector(symbolChanged)
        stack.addArrangedSubview(labeled(T("Simbolo", "Symbol"), symbol))

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        let hint = NSTextField(wrappingLabelWithString: T(
            "Un click sulla tile apre la cartella. I file trascinati sopra ci finiscono dentro, e il tasto destro mostra le cose arrivate per ultime.",
            "Clicking the tile opens the folder. Files dropped on it are moved inside, and right-click shows what arrived most recently."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(hint)

        updateLabel()
    }

    private func updateLabel() {
        guard let url = settings.url else {
            pathLabel?.stringValue = T("Nessuna cartella scelta.", "No folder chosen yet.")
            return
        }
        let count = monitor.count
        pathLabel?.stringValue = "\(url.path) — "
            + T("\(count) elementi", "\(count) items")
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // The stack in the Dock points at a path: moving the widget to another
        // folder has to take the old one out before putting the new one in.
        let previous = settings.url
        settings.path = url.path
        settings.save(instance)
        monitor.watch(url.path)
        updateLabel()
        if settings.place == .stack {
            WidgetInstaller.applyFolderPlace(for: instance, leaving: previous)
        }
        reloadTile()
    }

    @objc private func tintChanged(_ sender: NSPopUpButton) {
        settings.tintHex = FolderTints.all[sender.indexOfSelectedItem].hex
        settings.save(instance)
        reloadTile()
    }

    @objc private func symbolChanged(_ sender: NSPopUpButton) {
        settings.symbol = sender.indexOfSelectedItem == 0 ? "" : (sender.titleOfSelectedItem ?? "")
        settings.save(instance)
        reloadTile()
    }

    private func updatePreviewRows() {
        let isStack = settings.place == .stack
        placeRows.forEach { $0.isHidden = !isStack }
        clickRows.forEach { $0.isHidden = isStack }
        let showing = !isStack && settings.click == .preview
    }

    @objc private func placeChanged(_ sender: NSPopUpButton) {
        settings.place = FolderSettings.Place.allCases[sender.indexOfSelectedItem]
        settings.save(instance)
        updatePreviewRows()
        WidgetInstaller.applyFolderPlace(for: instance)
    }

    @objc private func stackViewChanged(_ sender: NSPopUpButton) {
        settings.stackView = FolderStack.View.allCases[sender.indexOfSelectedItem]
        settings.save(instance)
        WidgetInstaller.applyFolderPlace(for: instance)
    }

    @objc private func stackSortChanged(_ sender: NSPopUpButton) {
        settings.stackSort = FolderStack.Sort.allCases[sender.indexOfSelectedItem]
        settings.save(instance)
        WidgetInstaller.applyFolderPlace(for: instance)
    }

    @objc private func stackDisplayChanged(_ sender: NSPopUpButton) {
        settings.stackDisplay = FolderStack.Display.allCases[sender.indexOfSelectedItem]
        settings.save(instance)
        WidgetInstaller.applyFolderPlace(for: instance)
    }

    @objc private func clickChanged(_ sender: NSPopUpButton) {
        settings.click = FolderSettings.Click.allCases[sender.indexOfSelectedItem]
        settings.save(instance)
        updatePreviewRows()
        reloadTile()
    }

    @objc private func countChanged(_ sender: NSButton) {
        settings.showsCount = sender.state == .on
        settings.save(instance)
        reloadTile()
    }
}
