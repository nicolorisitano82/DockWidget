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
            "I file trascinati sulla tile vengono spostati dentro la cartella. Il tasto destro mostra le cose arrivate per ultime.",
            "Files dropped on the tile are moved into the folder. Right-click shows what arrived most recently."))
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

    @objc private func countChanged(_ sender: NSButton) {
        settings.showsCount = sender.state == .on
        settings.save()
        reloadTile()
    }
}
