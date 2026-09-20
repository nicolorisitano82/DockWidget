import AppKit

final class CalendarPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private var spec: BarLayout.Spec {
        BarLayout.calendar.forInstance(instance, anchorTitle: "")
    }

    private lazy var settings = CalendarSettings.current(instance)
    private var feedRow: NSView?
    private var widthField: NSTextField?
    private var daysField: NSTextField?

    override func makeStageView() -> NSView {
        let view = CalendarBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 88))
        view.instance = instance
        view.tileCount = spec.spacerCount + 1
        return view
    }

    override var stageSize: NSSize { NSSize(width: 300, height: 88) }
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

        let source = NSPopUpButton()
        for choice in CalendarSettings.Source.allCases { source.addItem(withTitle: choice.label) }
        source.selectItem(at: CalendarSettings.Source.allCases.firstIndex(of: settings.source) ?? 0)
        source.target = self
        source.action = #selector(sourceChanged)
        stack.addArrangedSubview(labeled(T("Da dove", "Where from"), source))

        let feed = NSTextField(string: settings.feedURL)
        feed.placeholderString = "https://calendar.google.com/calendar/ical/…/basic.ics"
        feed.target = self
        feed.action = #selector(feedChanged)
        let feedLabelled = labeled(T("Indirizzo", "Address"), feed)
        feedRow = feedLabelled
        stack.addArrangedSubview(feedLabelled)

        let explanation = NSTextField(wrappingLabelWithString: T(
            "Il calendario di Apple comprende anche gli account Google già aggiunti nelle Impostazioni di Sistema. L'indirizzo iCal serve per un calendario Google che questo Mac non ha: in Google Calendar, impostazioni del calendario → «Integra calendario» → «Indirizzo segreto in formato iCal». È di sola lettura.",
            "Apple Calendar already includes any Google account added in System Settings. The iCal address is for a Google calendar this Mac does not have: in Google Calendar, calendar settings → \"Integrate calendar\" → \"Secret address in iCal format\". It is read-only."))
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .tertiaryLabelColor
        explanation.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(explanation)

        let days = NSStepper()
        days.minValue = 1
        days.maxValue = 60
        days.increment = 1
        days.integerValue = settings.daysAhead
        days.target = self
        days.action = #selector(daysChanged)
        daysField = NSTextField(labelWithString: T("\(settings.daysAhead) giorni",
                                                    "\(settings.daysAhead) days"))
        let daysRow = NSStackView(views: [days, daysField!])
        daysRow.orientation = .horizontal
        daysRow.spacing = 8
        stack.addArrangedSubview(labeled(T("Fin dove guardare", "How far ahead"), daysRow))

        stack.addArrangedSubview(checkbox(T("Tieni quello in corso", "Keep the one running"),
                                          isOn: settings.showsCurrent,
                                          action: #selector(currentChanged)))
        stack.addArrangedSubview(checkbox(T("Mostra il luogo", "Show the location"),
                                          isOn: settings.showsLocation,
                                          action: #selector(locationChanged)))

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.store()
        }
        stack.addArrangedSubview(swatches)

        updateFeedRow()
    }

    private func updateFeedRow() {
        feedRow?.isHidden = settings.source != .feed
    }

    private func store() {
        settings.save(instance)
        CalendarStore.shared(instance).refresh()
        reloadTile()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        settings.source = CalendarSettings.Source.allCases[sender.indexOfSelectedItem]
        updateFeedRow()
        store()
    }

    @objc private func feedChanged(_ sender: NSTextField) {
        settings.feedURL = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        store()
    }

    @objc private func daysChanged(_ sender: NSStepper) {
        settings.daysAhead = sender.integerValue
        daysField?.stringValue = T("\(sender.integerValue) giorni", "\(sender.integerValue) days")
        store()
    }

    @objc private func currentChanged(_ sender: NSButton) {
        settings.showsCurrent = sender.state == .on
        store()
    }

    @objc private func locationChanged(_ sender: NSButton) {
        settings.showsLocation = sender.state == .on
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
