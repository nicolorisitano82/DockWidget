import AppKit

final class NotchPaneController: PaneViewController {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private var settings = NotchSettings.current
    private var slots: [NSPopUpButton] = []
    private var openLabel: NSTextField?
    private var closeLabel: NSTextField?

    override func makeStageView() -> NSView {
        NotchPreview(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
    }

    override var stageSize: NSSize { NSSize(width: 300, height: 120) }
    override func refreshTick() -> Bool { false }

    override func buildControls(in stack: NSStackView) {
        stack.addArrangedSubview(checkbox(T("Attiva la barra del notch", "Turn the notch bar on"),
                                          isOn: settings.isEnabled,
                                          action: #selector(enabledChanged)))

        for index in 0..<NotchSettings.maximumWidgets {
            let popup = NSPopUpButton()
            popup.addItem(withTitle: T("Nessuno", "None"))
            for instance in NotchOffer.all {
                popup.addItem(withTitle: NotchOffer.name(of: instance))
            }
            let chosen = index < settings.widgets.count ? settings.widgets[index] : ""
            popup.selectItem(at: chosen.isEmpty ? 0 : (NotchOffer.all.firstIndex(of: chosen).map { $0 + 1 } ?? 0))
            popup.tag = index
            popup.target = self
            popup.action = #selector(slotChanged)
            slots.append(popup)
            stack.addArrangedSubview(labeled(T("Riga \(index + 1)", "Row \(index + 1)"), popup))
        }

        stack.addArrangedSubview(sectionTitle(T("Ai lati del notch", "Either side of the notch")))

        for side in NotchSide.allCases {
            let popup = NSPopUpButton()
            for kind in NotchLevelKind.allCases { popup.addItem(withTitle: kind.label) }
            let chosen = settings.level(on: side)
            popup.selectItem(at: NotchLevelKind.allCases.firstIndex(of: chosen) ?? 0)
            popup.tag = side == .left ? 0 : 1
            popup.target = self
            popup.action = #selector(levelChanged)
            stack.addArrangedSubview(labeled(side.label, popup))
        }

        let step = NSPopUpButton()
        for choice in Self.steps { step.addItem(withTitle: "\(Int(1 / choice)) \(T("passi", "steps"))") }
        step.selectItem(at: Self.steps.firstIndex { abs($0 - settings.levelStep) < 0.001 } ?? 2)
        step.target = self
        step.action = #selector(stepChanged)
        stack.addArrangedSubview(labeled(T("Passo", "Step"), step))

        let levelsHint = NSTextField(wrappingLabelWithString: T(
            "Stanno dentro il pannello, nel nero ai lati del notch, e ci sono solo mentre è aperto. Mostrano l'intensità; un clic ingrossa la barretta per trascinarla, la rotella la muove di un passo. La luminosità compare solo se questo Mac la lascia leggere.",
            "They sit inside the panel, in the black either side of the notch, and are there only while it is open. They show the level; a click thickens the bar so you can drag it, the wheel moves it a step. Brightness appears only if this Mac lets it be read."))
        levelsHint.font = .systemFont(ofSize: 11)
        levelsHint.textColor = .tertiaryLabelColor
        levelsHint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(levelsHint)

        stack.addArrangedSubview(sectionTitle(T("Tempi", "Timing")))

        let open = delaySlider(settings.openDelay, #selector(openDelayChanged))
        openLabel = delayLabel(settings.openDelay)
        stack.addArrangedSubview(labeled(T("Ritardo di apertura", "Open delay"),
                                         pair(open, openLabel!)))

        let close = delaySlider(settings.closeDelay, #selector(closeDelayChanged))
        closeLabel = delayLabel(settings.closeDelay)
        stack.addArrangedSubview(labeled(T("Ritardo di chiusura", "Close delay"),
                                         pair(close, closeLabel!)))

        let timing = NSTextField(wrappingLabelWithString: T(
            "L'apertura ritardata evita che il pannello scenda mentre stai solo attraversando il bordo; la chiusura ritardata ti lascia il tempo di rientrare.",
            "The open delay keeps the panel up while you are only crossing the edge; the close delay gives you time to come back."))
        timing.font = .systemFont(ofSize: 11)
        timing.textColor = .tertiaryLabelColor
        timing.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(timing)

        let hint = NSTextField(wrappingLabelWithString: NotchGeometry.hasNotch
            ? T("Il pannello scende dal notch quando ci passi sopra il puntatore, e risale quando te ne vai.",
                "The panel comes down from the notch when the pointer arrives, and goes back up when it leaves.")
            : T("Questo Mac non ha un notch: il pannello scende comunque dal centro del bordo superiore.",
                "This Mac has no notch: the panel still comes down from the middle of the top edge."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(hint)
    }


    /// Whole fractions of the range, named by how many presses cross it: the
    /// keyboard's own keys are sixteenths.
    private static let steps: [Double] = [1.0 / 4, 1.0 / 8, 1.0 / 16, 1.0 / 32, 1.0 / 64]

    @objc private func levelChanged(_ sender: NSPopUpButton) {
        let kind = NotchLevelKind.allCases[sender.indexOfSelectedItem]
        if sender.tag == 0 { settings.leftLevel = kind } else { settings.rightLevel = kind }
        settings.save()
        if settings.isEnabled { BarAgent.start() }
    }

    @objc private func stepChanged(_ sender: NSPopUpButton) {
        settings.levelStep = Self.steps[sender.indexOfSelectedItem]
        settings.save()
    }

    private func delaySlider(_ value: TimeInterval, _ action: Selector) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1.5,
                              target: self, action: action)
        slider.numberOfTickMarks = 7
        slider.allowsTickMarkValuesOnly = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return slider
    }

    private func delayLabel(_ value: TimeInterval) -> NSTextField {
        let label = NSTextField(labelWithString: text(for: value))
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func pair(_ slider: NSSlider, _ label: NSTextField) -> NSStackView {
        let row = NSStackView(views: [slider, label])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func text(for value: TimeInterval) -> String {
        value < 0.02 ? T("subito", "instant") : String(format: "%.2f s", value)
    }

    @objc private func openDelayChanged(_ sender: NSSlider) {
        settings.openDelay = sender.doubleValue
        settings.save()
        openLabel?.stringValue = text(for: settings.openDelay)
    }

    @objc private func closeDelayChanged(_ sender: NSSlider) {
        settings.closeDelay = sender.doubleValue
        settings.save()
        closeLabel?.stringValue = text(for: settings.closeDelay)
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        settings.isEnabled = sender.state == .on
        settings.save()
        if settings.isEnabled { BarAgent.start() }
    }

    @objc private func slotChanged(_ sender: NSPopUpButton) {
        var chosen: [String] = []
        for popup in slots {
            let index = popup.indexOfSelectedItem
            guard index > 0, index - 1 < NotchOffer.all.count else { continue }
            let instance = NotchOffer.all[index - 1]
            if !chosen.contains(instance) { chosen.append(instance) }
        }
        settings.widgets = chosen
        settings.save()
        reloadTile()
    }

}

/// What can go in the notch, by instance identifier.
enum NotchOffer {
    /// The widgets that can go in the notch, as their notch instances.
    static let all = NotchOffering.instances

    static func name(of instance: String) -> String {
        WidgetCatalog.kinds.first { $0.kind == WidgetInstance.kind(of: instance) }?.baseName
            ?? instance
    }
}

/// A drawing of the notch panel, for the settings window.
final class NotchPreview: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let settings = NotchSettings.current
        let dark = SystemAppearance.shared.isDark
        let palette = TilePalette.resolve(dark: dark, accent: .systemBlue)

        let notch = NSRect(x: bounds.midX - 44, y: bounds.maxY - 14, width: 88, height: 14)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: notch, xRadius: 7, yRadius: 7).fill()

        let rows = max(settings.widgets.count, 1)
        let height = CGFloat(rows) * 22 + 16
        let panel = NSRect(x: bounds.midX - 110, y: notch.minY - height, width: 220, height: height)
        let path = NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14)
        palette.card.setFill()
        path.fill()
        palette.cardEdge.setStroke()
        path.stroke()

        for index in 0..<rows {
            let row = NSRect(x: panel.minX + 12,
                             y: panel.maxY - CGFloat(index + 1) * 22 - 6,
                             width: panel.width - 24, height: 16)
            palette.faint.setFill()
            NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()

            let label = index < settings.widgets.count
                ? NotchOffer.name(of: settings.widgets[index])
                : T("vuota", "empty")
            (label as NSString).draw(at: NSPoint(x: row.minX + 8, y: row.minY + 2),
                                     withAttributes: [
                                        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                        .foregroundColor: palette.secondary,
                                     ])
        }
    }
}
