import AppKit

final class AppleNotesPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private lazy var settings = AppleNotesSettings.current(instance)
    private var folderButton: NSPopUpButton?
    private var status: NSTextField?
    private var observer: NSObjectProtocol?

    override func makeStageView() -> NSView {
        guard settings.mode == .bar else {
            let view = AppleNotesTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            view.instance = instance
            return view
        }
        let view = AppleNotesBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 88))
        view.instance = instance
        view.tileCount = 4
        return view
    }

    override var stageSize: NSSize {
        settings.mode == .bar ? NSSize(width: 300, height: 88) : NSSize(width: 128, height: 128)
    }

    override func refreshTick() -> Bool { false }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard observer == nil else { return }
        observer = AppleNotesBridge.observe { [weak self] in
            self?.reloadFolders()
            self?.updateStatus()
            self?.reloadTile()
        }
        refresh()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    override func buildControls(in stack: NSStackView) {
        // A widget in the notch is always a bar.
        if !WidgetInstance.isNotch(instance) {
        let mode = NSSegmentedControl(labels: AppleNotesSettings.Mode.allCases.map(\.label),
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(modeChanged))
            mode.selectedSegment = AppleNotesSettings.Mode.allCases.firstIndex(of: settings.mode) ?? 0
            stack.addArrangedSubview(labeled(T("Formato", "Format"), mode))
        }

        let folders = NSPopUpButton()
        folders.target = self
        folders.action = #selector(folderChanged)
        folderButton = folders
        stack.addArrangedSubview(labeled(T("Cartella", "Folder"), folders))

        stack.addArrangedSubview(checkbox(T("Mostra l'inizio della nota", "Show the start of the note"),
                                          isOn: settings.showsSnippet,
                                          action: #selector(snippetChanged)))

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(self.instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        let refreshButton = NSButton(title: T("Aggiorna adesso", "Refresh now"),
                                     target: self, action: #selector(refresh))
        stack.addArrangedSubview(labeled("", refreshButton))

        let line = NSTextField(wrappingLabelWithString: "")
        line.font = .systemFont(ofSize: 11)
        line.textColor = .secondaryLabelColor
        line.preferredMaxLayoutWidth = 392
        status = line
        stack.addArrangedSubview(line)

        let hint = NSTextField(wrappingLabelWithString: T(
            "Note si raggiunge solo via AppleScript, quindi la prima lettura chiede il permesso di automazione. Chiedendolo da qui lo concedi a Underdock, e il resto legge quello che questa finestra ha pubblicato.",
            "Notes can only be reached through AppleScript, so the first read asks for the Automation permission. Asking from here grants it to Underdock, and everything else reads what this window published."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(hint)

        reloadFolders()
        updateStatus()
    }

    private func reloadFolders() {
        guard let folderButton else { return }
        let snapshot = AppleNotesBridge.read()
        folderButton.removeAllItems()
        folderButton.addItem(withTitle: T("Tutte", "All"))
        folderButton.addItems(withTitles: snapshot.folders)
        folderButton.selectItem(withTitle: settings.folder.isEmpty ? T("Tutte", "All") : settings.folder)
    }

    private func updateStatus() {
        let snapshot = AppleNotesBridge.read()
        if let failure = snapshot.failure {
            status?.stringValue = failure
            return
        }
        guard snapshot.fetchedAt > .distantPast else {
            status?.stringValue = T("Mai letto.", "Never read.")
            return
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        status?.stringValue = T("\(snapshot.notes.count) note, lette \(formatter.localizedString(for: snapshot.fetchedAt, relativeTo: Date()))",
                                "\(snapshot.notes.count) notes, read \(formatter.localizedString(for: snapshot.fetchedAt, relativeTo: Date()))")
    }

    @objc private func refresh() {
        status?.stringValue = T("Lettura in corso…", "Reading…")
        AppleNotesBridge.refresh(folder: settings.folder)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        settings.mode = AppleNotesSettings.Mode.allCases[sender.selectedSegment]
        settings.save(instance)
        WidgetInstaller.applyBarMode(for: instance)
        onRequestReload?()
    }

    @objc private func folderChanged(_ sender: NSPopUpButton) {
        settings.folder = sender.indexOfSelectedItem == 0 ? "" : (sender.titleOfSelectedItem ?? "")
        settings.save(instance)
        refresh()
    }

    @objc private func snippetChanged(_ sender: NSButton) {
        settings.showsSnippet = sender.state == .on
        settings.save(instance)
        reloadTile()
    }
}
