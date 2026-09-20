import AppKit

extension Notification.Name {
    /// Posted by a widget helper when its tile is clicked.
    static let selectWidget = Notification.Name("dev.nicolo.dockwidgets.selectWidget")
}

final class ManagerViewController: NSViewController {
    private let sidebar = NSStackView()
    private let detailContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let copyButton = NSPopUpButton()
    private let addCopyButton = NSButton(title: "+", target: nil, action: nil)
    private let removeCopyButton = NSButton(title: "−", target: nil, action: nil)
    private let dockSwitch = NSSwitch()
    private var rows: [WidgetRowView] = []
    private var pane: PaneViewController?

    private var selectedKind = 0
    private var selectedCopy = 1

    private var kinds: [WidgetDescriptor] { WidgetCatalog.kinds }
    private var copies: [WidgetDescriptor] { WidgetCatalog.copies(of: kinds[selectedKind]) }
    private var widget: WidgetDescriptor? {
        copies.first { $0.copy == selectedCopy } ?? copies.first
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 620))

        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 4
        sidebar.edgeInsets = NSEdgeInsets(top: 16, left: 10, bottom: 12, right: 10)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: T("WIDGET", "WIDGETS"))
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = .tertiaryLabelColor
        sidebar.addArrangedSubview(heading)

        for (index, kind) in kinds.enumerated() {
            let row = WidgetRowView(widget: kind)
            row.onClick = { [weak self] in self?.select(kind: index) }
            rows.append(row)
            sidebar.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 196).isActive = true
        }

        sidebar.addArrangedSubview(NSView())
        let hint = NSTextField(wrappingLabelWithString: T(
            "Attivando o disattivando un widget il Dock si riavvia: è l'unico modo per fargli rileggere le sue preferenze.",
            "Turning a widget on or off restarts the Dock: it is the only way to make it re-read its preferences."))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 196
        sidebar.addArrangedSubview(hint)

        let sidebarBackground = NSVisualEffectView()
        sidebarBackground.material = .sidebar
        sidebarBackground.state = .followsWindowActiveState
        sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackground.addSubview(sidebar)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        copyButton.target = self
        copyButton.action = #selector(copyChanged)

        dockSwitch.target = self
        dockSwitch.action = #selector(toggleInstalled)
        let switchLabel = NSTextField(labelWithString: T("Nel Dock", "In the Dock"))
        switchLabel.font = .systemFont(ofSize: 12, weight: .medium)

        addCopyButton.bezelStyle = .circular
        addCopyButton.target = self
        addCopyButton.action = #selector(addCopy)
        addCopyButton.toolTip = T("Aggiungi una copia di questo widget",
                                  "Add another copy of this widget")

        removeCopyButton.bezelStyle = .circular
        removeCopyButton.target = self
        removeCopyButton.action = #selector(removeCopy)
        removeCopyButton.toolTip = T("Elimina questa copia", "Delete this copy")

        let headerRow = NSStackView(views: [titleLabel, copyButton, addCopyButton, removeCopyButton,
                                            NSView(), switchLabel, dockSwitch])
        headerRow.orientation = .horizontal
        headerRow.spacing = 10
        headerRow.alignment = .centerY

        let header = NSStackView(views: [headerRow, summaryLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(header)
        detail.addSubview(detailContainer)

        root.addSubview(sidebarBackground)
        root.addSubview(detail)

        NSLayoutConstraint.activate([
            sidebarBackground.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarBackground.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarBackground.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarBackground.widthAnchor.constraint(equalToConstant: 216),
            sidebar.topAnchor.constraint(equalTo: sidebarBackground.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: sidebarBackground.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: sidebarBackground.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),

            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            header.topAnchor.constraint(equalTo: detail.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -24),

            detailContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            detailContainer.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        select(kind: selectedKind)
    }

    /// Brings up a widget by instance identifier, which is how a click on a
    /// tile arrives: "clock2" selects the clock, second copy.
    func select(instance: String) {
        let kind = WidgetInstance.kind(of: instance)
        guard let index = kinds.firstIndex(where: { $0.kind == kind }) else { return }
        select(kind: index, copy: WidgetInstance.copy(of: instance))
    }

    func select(kind index: Int, copy: Int = 1) {
        guard index >= 0, index < kinds.count else { return }
        selectedKind = index
        selectedCopy = copy

        for (position, row) in rows.enumerated() {
            row.isSelected = position == index
            row.isInstalled = WidgetCatalog.copies(of: kinds[position]).contains { $0.isInstalled }
        }

        copyButton.removeAllItems()
        for descriptor in copies {
            copyButton.addItem(withTitle: descriptor.copy <= 1
                               ? T("Prima copia", "First copy")
                               : T("Copia \(descriptor.copy)", "Copy \(descriptor.copy)"))
        }
        copyButton.selectItem(at: copies.firstIndex { $0.copy == selectedCopy } ?? 0)
        let replicable = kinds[selectedKind].isReplicable
        copyButton.isHidden = !replicable || copies.count < 2
        addCopyButton.isHidden = !replicable
        removeCopyButton.isHidden = !replicable
        // The first copy ships with the app and stays.
        removeCopyButton.isEnabled = selectedCopy > 1

        guard let widget else { return }
        titleLabel.stringValue = widget.name
        summaryLabel.stringValue = widget.summary
        dockSwitch.state = widget.isInstalled ? .on : .off

        pane?.view.removeFromSuperview()
        pane?.removeFromParent()

        let controller = widget.makePane()
        controller.onRequestReload = { [weak self] in
            guard let self else { return }
            self.select(kind: self.selectedKind, copy: self.selectedCopy)
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(lessThanOrEqualTo: detailContainer.trailingAnchor),
        ])
        pane = controller
    }

    @objc private func copyChanged(_ sender: NSPopUpButton) {
        let copy = copies[max(0, sender.indexOfSelectedItem)].copy
        select(kind: selectedKind, copy: copy)
    }

    @objc private func addCopy() {
        guard kinds[selectedKind].isReplicable,
              let created = InstanceFactory.create(from: kinds[selectedKind]) else { return }
        select(kind: selectedKind, copy: created.copy)
    }

    @objc private func removeCopy() {
        guard let widget, widget.copy > 1 else { return }

        let alert = NSAlert()
        alert.messageText = T("Eliminare \(widget.name)?", "Delete \(widget.name)?")
        alert.informativeText = T(
            "La copia esce dal Dock e le sue impostazioni vengono dimenticate. Le altre copie restano come sono.",
            "The copy leaves the Dock and its settings are forgotten. The other copies are untouched.")
        alert.addButton(withTitle: T("Elimina", "Delete"))
        alert.addButton(withTitle: T("Annulla", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        InstanceFactory.destroy(widget)
        select(kind: selectedKind, copy: 1)
    }

    @objc private func toggleInstalled() {
        guard let widget else { return }
        if dockSwitch.state == .on, !isInstalledInApplications {
            dockSwitch.state = .off
            let alert = NSAlert()
            alert.messageText = T("Sposta prima Dock Widgets in Applicazioni",
                                  "Move Dock Widgets to Applications first")
            let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
            alert.informativeText = T(
                "Questa copia gira da \(folder). Il Dock punterebbe lì, e quella cartella viene ricreata a ogni compilazione: la tile resterebbe orfana.",
                "This copy runs from \(folder). The Dock would point there, and that folder is rebuilt on every compile: the tile would be left orphaned.")
            alert.runModal()
            return
        }

        if dockSwitch.state == .on {
            WidgetInstaller.install(widget)
        } else {
            WidgetInstaller.uninstall(widget)
        }
        refreshInstallState()
    }

    /// A widget pinned from a build folder breaks on the next build.
    private var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    private func refreshInstallState() {
        for (index, row) in rows.enumerated() {
            row.isInstalled = WidgetCatalog.copies(of: kinds[index]).contains { $0.isInstalled }
        }
        dockSwitch.state = widget?.isInstalled == true ? .on : .off
    }
}

/// One clickable row in the sidebar: icon, name, and a dot when any copy of it
/// is in the Dock.
final class WidgetRowView: NSView {
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { updateAppearance() }
    }

    var isInstalled: Bool {
        didSet { dot.isHidden = !isInstalled }
    }

    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    init(widget: WidgetDescriptor) {
        isInstalled = widget.isInstalled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let imageView = NSImageView(image: widget.icon)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        label.stringValue = widget.baseName
        label.font = .systemFont(ofSize: 13)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 3
        dot.isHidden = !isInstalled

        let stack = NSStackView(views: [imageView, label, NSView(), dot])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
        label.textColor = isSelected ? .white : .labelColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
