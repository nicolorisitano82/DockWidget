import AppKit

final class FolderPaneController: PaneViewController {
    private var settings = FolderSettings.current
    private var pathLabel: NSTextField?
    private var token: UUID?

    override func makeTileView() -> TileView {
        FolderTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func refreshTick() -> Bool { false }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard token == nil else { return }
        token = FolderMonitor.shared.addListener { [weak self] in
            self?.updateLabel()
            self?.reloadTile()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let token { FolderMonitor.shared.removeListener(token) }
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
            self.settings.save()
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
        let count = FolderMonitor.shared.count
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
        settings.path = url.path
        settings.save()
        FolderMonitor.shared.watch(url.path)
        updateLabel()
        reloadTile()
    }

    @objc private func tintChanged(_ sender: NSPopUpButton) {
        settings.tintHex = FolderTints.all[sender.indexOfSelectedItem].hex
        settings.save()
        reloadTile()
    }

    @objc private func symbolChanged(_ sender: NSPopUpButton) {
        settings.symbol = sender.indexOfSelectedItem == 0 ? "" : (sender.titleOfSelectedItem ?? "")
        settings.save()
        reloadTile()
    }

    @objc private func countChanged(_ sender: NSButton) {
        settings.showsCount = sender.state == .on
        settings.save()
        reloadTile()
    }
}
