import AppKit

final class ShelfPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private var spec: BarLayout.Spec {
        BarLayout.shelf.forInstance(instance, anchorTitle: "")
    }

    private lazy var settings = ShelfSettings.current(instance)
    private var summary: NSTextField?
    private var widthField: NSTextField?

    override func makeStageView() -> NSView {
        let view = ShelfBarView(frame: NSRect(x: 0, y: 0, width: 260, height: 88))
        view.instance = instance
        view.tileCount = spec.spacerCount + 1
        return view
    }

    override var stageSize: NSSize { NSSize(width: 260, height: 88) }
    override func refreshTick() -> Bool { false }

    override func buildControls(in stack: NSStackView) {
        if !WidgetInstance.isNotch(instance) {
            let width = NSStepper()
            width.minValue = Double(spec.minimumSpacers)
            width.maxValue = Double(spec.maximumSpacers)
            width.increment = 1
            width.integerValue = spec.spacerCount
            width.target = self
            width.action = #selector(widthChanged)
            widthField = NSTextField(labelWithString: T("\(spec.spacerCount + 1) tile",
                                                         "\(spec.spacerCount + 1) tiles"))
            let row = NSStackView(views: [width, widthField!])
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(labeled(T("Larghezza", "Width"), row))
        }

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(self.instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        let line = NSTextField(wrappingLabelWithString: "")
        line.font = .systemFont(ofSize: 11.5)
        line.textColor = .secondaryLabelColor
        line.preferredMaxLayoutWidth = 392
        summary = line
        stack.addArrangedSubview(line)

        let empty = NSButton(title: T("Svuota la mensola", "Empty the shelf"),
                             target: self, action: #selector(emptyShelf))
        stack.addArrangedSubview(labeled("", empty))

        let hint = NSTextField(wrappingLabelWithString: T(
            "I file non vengono spostati né copiati: la mensola tiene solo dove sono. Trascinali sopra per posarli, trascinali via per riprenderli.",
            "Files are neither moved nor copied: the shelf only keeps where they are. Drag them on to put them down, drag them off to take them back."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(hint)

        updateSummary()
    }

    private func updateSummary() {
        let count = ShelfSettings.current(instance).paths.count
        summary?.stringValue = count == 0
            ? T("La mensola è vuota.", "The shelf is empty.")
            : T("\(count) file, al massimo \(ShelfSettings.capacity).",
                "\(count) files, up to \(ShelfSettings.capacity).")
    }

    @objc private func emptyShelf() {
        var updated = ShelfSettings.current(instance)
        updated.paths = []
        updated.save(instance)
        updateSummary()
        reloadTile()
    }

    @objc private func widthChanged(_ sender: NSStepper) {
        let count = min(max(sender.integerValue, spec.minimumSpacers), spec.maximumSpacers)
        sender.integerValue = count
        SettingsStore.shared.set(Double(count), for: spec.spacerCountKey)
        widthField?.stringValue = T("\(count + 1) tile", "\(count + 1) tiles")
        WidgetInstaller.applyBarMode(for: instance)
        reloadTile()
    }
}
