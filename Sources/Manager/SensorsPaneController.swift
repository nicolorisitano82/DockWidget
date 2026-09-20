import AppKit

final class SensorsPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private lazy var settings = SensorsSettings.current(instance)
    private var barRows: NSStackView?
    private var widthField: NSTextField?

    override func makeStageView() -> NSView {
        guard settings.mode == .bar else {
            let view = SensorsTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        view.instance = instance
        return view
        }
        let view = SensorsBarView(frame: NSRect(x: 0, y: 0, width: 240, height: 88))
        view.instance = instance
        view.tileCount = BarLayout.sensors.spacerCount + 1
        return view
    }

    override var stageSize: NSSize {
        settings.mode == .bar ? NSSize(width: 240, height: 88) : NSSize(width: 128, height: 128)
    }

    override func refreshTick() -> Bool { false }

    override func buildControls(in stack: NSStackView) {
        // A widget in the notch is always a bar.
        if !WidgetInstance.isNotch(instance) {
        let mode = NSSegmentedControl(labels: SensorsSettings.Mode.allCases.map(\.label),
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(modeChanged))
            mode.selectedSegment = SensorsSettings.Mode.allCases.firstIndex(of: settings.mode) ?? 0
            stack.addArrangedSubview(labeled(T("Formato", "Format"), mode))
        }

        if settings.mode == .tile {
            let sensor = NSPopUpButton()
            sensor.addItems(withTitles: SensorID.available.map(\.label))
            sensor.selectItem(at: SensorID.available.firstIndex(of: settings.tileSensor) ?? 0)
            sensor.target = self
            sensor.action = #selector(tileSensorChanged)
            stack.addArrangedSubview(labeled(T("Sensore", "Sensor"), sensor))
        } else {
            let spec = BarLayout.sensors
            let width = NSStepper()
            width.minValue = Double(spec.minimumSpacers)
            width.maxValue = Double(spec.maximumSpacers)
            width.increment = 1
            width.integerValue = spec.spacerCount
            width.target = self
            width.action = #selector(widthChanged)
            let label = NSTextField(labelWithString: T("\(spec.spacerCount + 1) sensori",
                                                   "\(spec.spacerCount + 1) sensors"))
            widthField = label
            let row = NSStackView(views: [width, label])
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(labeled(T("Larghezza", "Width"), row))

            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.spacing = 8
            barRows = rows
            stack.addArrangedSubview(rows)
            rebuildBarRows()
        }

        let refresh = NSPopUpButton()
        refresh.addItems(withTitles: [T("1 secondo", "1 second"), T("2 secondi", "2 seconds"), T("5 secondi", "5 seconds")])
        refresh.selectItem(at: [1.0, 2.0, 5.0].firstIndex(of: settings.refresh) ?? 1)
        refresh.target = self
        refresh.action = #selector(refreshChanged)
        stack.addArrangedSubview(labeled(T("Aggiornamento", "Refresh"), refresh))

        stack.addArrangedSubview(checkbox(T("Mostra l'andamento", "Show the trend"), isOn: settings.showsSparkline,
                                          action: #selector(sparklineChanged)))

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)
    }

    /// One popup per cell the bar can show. The list of chosen sensors is
    /// longer than the bar when the bar is narrow; the extra entries stay in
    /// the settings and come back when it widens again.
    private func rebuildBarRows() {
        guard let barRows else { return }
        barRows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let visible = settings.visibleBarSensors(count: BarLayout.sensors.spacerCount + 1)
        for (index, sensor) in visible.enumerated() {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: SensorID.available.map(\.label))
            popup.selectItem(at: SensorID.available.firstIndex(of: sensor) ?? 0)
            popup.tag = index
            popup.target = self
            popup.action = #selector(barSensorChanged)
            barRows.addArrangedSubview(labeled(T("Cella \(index + 1)", "Cell \(index + 1)"), popup))
        }
    }

    // MARK: Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        settings.mode = SensorsSettings.Mode.allCases[sender.selectedSegment]
        settings.save(instance)
        WidgetInstaller.applyBarMode(for: "sensors")
        // The preview changes shape with the mode, so the pane is rebuilt.
        onRequestReload?()
    }

    @objc private func tileSensorChanged(_ sender: NSPopUpButton) {
        settings.tileSensor = SensorID.available[sender.indexOfSelectedItem]
        settings.save(instance)
        reloadTile()
    }

    @objc private func barSensorChanged(_ sender: NSPopUpButton) {
        var chosen = settings.visibleBarSensors(count: BarLayout.sensors.spacerCount + 1)
        guard sender.tag < chosen.count else { return }
        chosen[sender.tag] = SensorID.available[sender.indexOfSelectedItem]

        // Keep whatever was configured beyond the current width.
        var full = settings.barSensors
        while full.count < chosen.count { full.append(chosen[full.count]) }
        for (index, sensor) in chosen.enumerated() { full[index] = sensor }
        settings.barSensors = full
        settings.save(instance)
        reloadTile()
    }

    @objc private func widthChanged(_ sender: NSStepper) {
        let spec = BarLayout.sensors
        let count = min(max(sender.integerValue, spec.minimumSpacers), spec.maximumSpacers)
        sender.integerValue = count
        SettingsStore.shared.set(Double(count), for: spec.spacerCountKey)
        widthField?.stringValue = T("\(count + 1) sensori", "\(count + 1) sensors")
        rebuildBarRows()
        WidgetInstaller.applyBarMode(for: "sensors")
        reloadTile()
    }

    @objc private func refreshChanged(_ sender: NSPopUpButton) {
        settings.refresh = [1.0, 2.0, 5.0][sender.indexOfSelectedItem]
        settings.save(instance)
        SensorSampler.shared.setInterval(settings.refresh)
    }

    @objc private func sparklineChanged(_ sender: NSButton) {
        settings.showsSparkline = sender.state == .on
        settings.save(instance)
        reloadTile()
    }
}
