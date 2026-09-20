import AppKit

final class DisksPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private lazy var settings = DisksSettings.current(instance)
    private var token: UUID?
    private var volumeButton: NSPopUpButton?
    private var summary: NSTextField?

    override func makeStageView() -> NSView {
        guard settings.mode == .bar else {
            let view = DisksTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        view.instance = instance
        return view
        }
        let view = DisksBarView(frame: NSRect(x: 0, y: 0, width: 240, height: 88))
        view.instance = instance
        view.tileCount = BarLayout.disks.spacerCount + 1
        return view
    }

    override var stageSize: NSSize {
        settings.mode == .bar ? NSSize(width: 240, height: 88) : NSSize(width: 128, height: 128)
    }

    override func refreshTick() -> Bool { false }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard token == nil else { return }
        token = VolumeScanner.shared.addListener { [weak self] in
            self?.reloadVolumes()
            self?.reloadTile()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let token { VolumeScanner.shared.removeListener(token) }
        token = nil
    }

    override func buildControls(in stack: NSStackView) {
        // A widget in the notch is always a bar.
        if !WidgetInstance.isNotch(instance) {
        let mode = NSSegmentedControl(labels: DisksSettings.Mode.allCases.map(\.label),
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(modeChanged))
            mode.selectedSegment = DisksSettings.Mode.allCases.firstIndex(of: settings.mode) ?? 0
            stack.addArrangedSubview(labeled(T("Formato", "Format"), mode))
        }

        if settings.mode == .tile {
            let volumes = NSPopUpButton()
            volumes.target = self
            volumes.action = #selector(volumeChanged)
            volumeButton = volumes
            stack.addArrangedSubview(labeled(T("Volume", "Volume"), volumes))

            stack.addArrangedSubview(checkbox(T("Mostra lo spazio libero", "Show free space"),
                                              isOn: settings.showsFree,
                                              action: #selector(freeChanged)))
        } else {
            let spec = BarLayout.disks
            let width = NSStepper()
            width.minValue = Double(spec.minimumSpacers)
            width.maxValue = Double(spec.maximumSpacers)
            width.increment = 1
            width.integerValue = spec.spacerCount
            width.target = self
            width.action = #selector(widthChanged)
            let label = NSTextField(labelWithString: T("\(spec.spacerCount + 1) volumi",
                                                       "\(spec.spacerCount + 1) volumes"))
            widthField = label
            let row = NSStackView(views: [width, label])
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(labeled(T("Larghezza", "Width"), row))
        }

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        stack.addArrangedSubview(sectionTitle(T("Montati ora", "Mounted now")))
        let list = NSTextField(wrappingLabelWithString: "")
        list.font = .systemFont(ofSize: 11.5)
        list.textColor = .secondaryLabelColor
        list.preferredMaxLayoutWidth = 392
        summary = list
        stack.addArrangedSubview(list)

        reloadVolumes()
    }

    private var widthField: NSTextField?

    private func reloadVolumes() {
        let volumes = VolumeScanner.shared.volumes
        if let volumeButton {
            volumeButton.removeAllItems()
            volumeButton.addItems(withTitles: volumes.map(\.name))
            if let index = volumes.firstIndex(where: { $0.name == settings.tileVolume }) {
                volumeButton.selectItem(at: index)
            }
        }
        summary?.stringValue = volumes.map { volume in
            let kind = volume.isBoot
                ? T("avvio", "boot")
                : (volume.isRemovable || !volume.isInternal ? T("esterno", "external")
                                                            : T("interno", "internal"))
            return "\(volume.name) · \(kind) · \(SensorFormat.bytes(Double(volume.free))) "
                + T("liberi su", "free of") + " \(SensorFormat.bytes(Double(volume.total)))"
        }.joined(separator: "\n")
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        settings.mode = DisksSettings.Mode.allCases[sender.selectedSegment]
        settings.save(instance)
        WidgetInstaller.applyBarMode(for: "disks")
        onRequestReload?()
    }

    @objc private func volumeChanged(_ sender: NSPopUpButton) {
        settings.tileVolume = sender.titleOfSelectedItem ?? ""
        settings.save(instance)
        reloadTile()
    }

    @objc private func freeChanged(_ sender: NSButton) {
        settings.showsFree = sender.state == .on
        settings.save(instance)
        reloadTile()
    }

    @objc private func widthChanged(_ sender: NSStepper) {
        let spec = BarLayout.disks
        let count = min(max(sender.integerValue, spec.minimumSpacers), spec.maximumSpacers)
        sender.integerValue = count
        SettingsStore.shared.set(Double(count), for: spec.spacerCountKey)
        widthField?.stringValue = T("\(count + 1) volumi", "\(count + 1) volumes")
        WidgetInstaller.applyBarMode(for: "disks")
        reloadTile()
    }
}
