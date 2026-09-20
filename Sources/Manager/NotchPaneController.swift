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

        let width = NSStepper()
        width.minValue = 320
        width.maxValue = 720
        width.increment = 20
        width.doubleValue = Double(settings.expandedWidth)
        width.target = self
        width.action = #selector(widthChanged)
        widthField = NSTextField(labelWithString: "\(Int(settings.expandedWidth)) pt")
        let row = NSStackView(views: [width, widthField!])
        row.orientation = .horizontal
        row.spacing = 8
        stack.addArrangedSubview(labeled(T("Larghezza aperta", "Open width"), row))

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

    private var widthField: NSTextField?

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

    @objc private func widthChanged(_ sender: NSStepper) {
        settings.expandedWidth = CGFloat(sender.doubleValue)
        settings.save()
        widthField?.stringValue = "\(Int(settings.expandedWidth)) pt"
        reloadTile()
    }
}

/// What can go in the notch, by instance identifier.
enum NotchOffer {
    static let all = ["nowplaying", "sensors", "disks", "actions", "note", "applenotes"]

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
