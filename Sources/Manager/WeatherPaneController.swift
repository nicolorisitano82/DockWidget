import AppKit

final class WeatherPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private var spec: BarLayout.Spec {
        BarLayout.weather.forInstance(instance, anchorTitle: "")
    }

    private lazy var settings = WeatherSettings.current(instance)
    private var results: [WeatherPlace] = []
    private var resultsButton: NSPopUpButton?
    private var searchField: NSTextField?
    private var placeName: NSTextField?
    private var placeDetail: NSTextField?
    private var widthField: NSTextField?

    override func makeStageView() -> NSView {
        let view = WeatherBarView(frame: NSRect(x: 0, y: 0, width: 260, height: 88))
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

        // The place the widget is actually set to, said plainly and kept in
        // view: choosing a city and then not being able to tell which one is
        // set was the whole trouble with the first version of this pane.
        stack.addArrangedSubview(sectionTitle(T("Posto", "Place")))
        stack.addArrangedSubview(placeCard())

        let search = NSTextField(string: settings.place)
        search.placeholderString = T("Cerca una città e premi Invio…",
                                     "Search for a town and press Return…")
        search.target = self
        search.action = #selector(searchChanged)
        searchField = search
        stack.addArrangedSubview(labeled(T("Cerca", "Search"), search))

        let found = NSPopUpButton()
        found.addItem(withTitle: settings.hasPlace ? settings.fullPlace : T("—", "—"))
        found.target = self
        found.action = #selector(placeChosen)
        found.isEnabled = false
        resultsButton = found
        stack.addArrangedSubview(labeled(T("Risultati", "Results"), found))

        let units = NSPopUpButton()
        for choice in WeatherSettings.Units.allCases { units.addItem(withTitle: choice.label) }
        units.selectItem(at: WeatherSettings.Units.allCases.firstIndex(of: settings.units) ?? 0)
        units.target = self
        units.action = #selector(unitsChanged)
        stack.addArrangedSubview(labeled(T("Gradi", "Degrees"), units))

        stack.addArrangedSubview(checkbox(T("Minima e massima", "Low and high"),
                                          isOn: settings.showsRange,
                                          action: #selector(rangeChanged)))

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.store()
        }
        stack.addArrangedSubview(swatches)

        let credit = NSTextField(wrappingLabelWithString: T(
            "Previsioni di Open-Meteo, che risponde senza chiave e senza account. Il posto si cerca per nome: nessun accesso alla posizione del Mac.",
            "Forecast by Open-Meteo, which answers without a key and without an account. The place is searched by name: no access to where this Mac is."))
        credit.font = .systemFont(ofSize: 11)
        credit.textColor = .tertiaryLabelColor
        credit.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(credit)
    }

    /// A line you cannot miss: a pin, the town, and where it is.
    private func placeCard() -> NSView {
        let pin = NSImageView(image: NSImage(systemSymbolName: "mappin.circle.fill",
                                             accessibilityDescription: nil) ?? NSImage())
        pin.contentTintColor = .controlAccentColor
        pin.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)

        let name = NSTextField(labelWithString: "")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        placeName = name

        let detail = NSTextField(labelWithString: "")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        placeDetail = detail

        let words = NSStackView(views: [name, detail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1

        let row = NSStackView(views: [pin, words])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor

        showPlace()
        return row
    }

    private func showPlace() {
        placeName?.stringValue = settings.hasPlace
            ? settings.place
            : T("Nessun posto", "No place yet")
        placeDetail?.stringValue = settings.hasPlace
            ? (settings.region.isEmpty
                ? String(format: "%.3f, %.3f", settings.latitude, settings.longitude)
                : settings.region)
            : T("Cercane uno qui sotto.", "Search for one below.")
    }

    private func store() {
        settings.save(instance)
        WeatherStore.shared(instance).refresh()
        reloadTile()
    }

    @objc private func searchChanged(_ sender: NSTextField) {
        WeatherStore.search(sender.stringValue) { [weak self] places in
            guard let self, let button = self.resultsButton else { return }
            self.results = places
            button.removeAllItems()
            if places.isEmpty {
                button.addItem(withTitle: T("Nessun risultato", "Nothing found"))
                button.isEnabled = false
                return
            }
            places.forEach { button.addItem(withTitle: $0.label) }
            button.isEnabled = true
            // The first hit is almost always the one meant, so it is applied
            // straight away and the list is there to correct it.
            button.selectItem(at: 0)
            self.apply(places[0])
        }
    }

    @objc private func placeChosen(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < results.count else { return }
        apply(results[index])
    }

    private func apply(_ place: WeatherPlace) {
        settings.place = place.name
        settings.region = place.region
        settings.latitude = place.latitude
        settings.longitude = place.longitude
        showPlace()
        // The field keeps what was chosen rather than what was typed, so the
        // pane says the same thing in all three places.
        searchField?.stringValue = place.name
        store()
    }

    @objc private func unitsChanged(_ sender: NSPopUpButton) {
        settings.units = WeatherSettings.Units.allCases[sender.indexOfSelectedItem]
        store()
    }

    @objc private func rangeChanged(_ sender: NSButton) {
        settings.showsRange = sender.state == .on
        store()
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
