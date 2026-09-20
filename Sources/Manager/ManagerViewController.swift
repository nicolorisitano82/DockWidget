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
    private let dockSwitch = NSSwitch()
    private var rows: [WidgetRowView] = []
    private var pane: PaneViewController?
    private var selectedIndex = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))

        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 4
        sidebar.edgeInsets = NSEdgeInsets(top: 16, left: 10, bottom: 12, right: 10)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: T("WIDGET", "WIDGETS"))
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = .tertiaryLabelColor
        sidebar.addArrangedSubview(heading)

        for (index, widget) in WidgetCatalog.all.enumerated() {
            let row = WidgetRowView(widget: widget)
            row.onClick = { [weak self] in self?.select(index) }
            rows.append(row)
            sidebar.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 196).isActive = true
        }

        sidebar.addArrangedSubview(NSView())
        let hint = NSTextField(wrappingLabelWithString:
            T("Attivando o disattivando un widget il Dock si riavvia: è l'unico modo per fargli rileggere le sue preferenze.", "Turning a widget on or off restarts the Dock: it is the only way to make it re-read its preferences."))
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

        dockSwitch.target = self
        dockSwitch.action = #selector(toggleInstalled)
        let switchLabel = NSTextField(labelWithString: T("Nel Dock", "In the Dock"))
        switchLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let headerRow = NSStackView(views: [titleLabel, NSView(), switchLabel, dockSwitch])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
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
        select(selectedIndex)
    }

    func select(_ index: Int) {
        guard index >= 0, index < WidgetCatalog.all.count else { return }
        selectedIndex = index
        let widget = WidgetCatalog.all[index]

        for (position, row) in rows.enumerated() {
            row.isSelected = position == index
        }

        titleLabel.stringValue = widget.name
        summaryLabel.stringValue = widget.summary
        dockSwitch.state = widget.isInstalled ? .on : .off

        pane?.view.removeFromSuperview()
        pane?.removeFromParent()

        let controller = widget.makePane()
        controller.onRequestReload = { [weak self] in self?.select(index) }
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

    @objc private func toggleInstalled() {
        let widget = WidgetCatalog.all[selectedIndex]
        if dockSwitch.state == .on, !isInstalledInApplications {
            dockSwitch.state = .off
            let alert = NSAlert()
            alert.messageText = T("Sposta prima Dock Widgets in Applicazioni", "Move Dock Widgets to Applications first")
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
            row.isInstalled = WidgetCatalog.all[index].isInstalled
        }
        dockSwitch.state = WidgetCatalog.all[selectedIndex].isInstalled ? .on : .off
    }
}

/// One clickable row in the sidebar: icon, name, and a dot when it is in the Dock.
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

        label.stringValue = widget.name
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
