import AppKit

/// Shared scaffolding: a live tile over a dock-like strip, a column of
/// controls, and the footer that puts the app in the Dock.
class PaneViewController: NSViewController {
    private(set) var stageView: NSView!

    /// Most panes preview a square tile; a bar widget previews a strip.
    var tileView: TileView? { stageView as? TileView }
    private var timer: Timer?

    private let controlsStack = NSStackView()

    // MARK: Subclass hooks

    func makeTileView() -> TileView { TileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128)) }
    /// Override to preview something other than a square tile.
    func makeStageView() -> NSView { makeTileView() }
    var stageSize: NSSize { NSSize(width: 128, height: 128) }
    func buildControls(in stack: NSStackView) {}
    /// Called once a second; return true when the tile needs redrawing.
    func refreshTick() -> Bool { true }

    // MARK: Layout

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 40))
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 18
        column.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 18, right: 24)
        column.translatesAutoresizingMaskIntoConstraints = false

        column.addArrangedSubview(makeStage())
        column.setCustomSpacing(22, after: column.arrangedSubviews[0])

        controlsStack.orientation = .vertical
        controlsStack.alignment = .leading
        controlsStack.spacing = 12
        buildControls(in: controlsStack)
        column.addArrangedSubview(controlsStack)

        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.widthAnchor.constraint(equalToConstant: 440),
        ])
        view = root
    }

    private func makeStage() -> NSView {
        let strip = NSVisualEffectView()
        strip.material = .hudWindow
        strip.state = .active
        strip.blendingMode = .behindWindow
        strip.wantsLayer = true
        strip.layer?.cornerRadius = 26
        strip.layer?.cornerCurve = .continuous
        strip.layer?.borderWidth = 1
        strip.layer?.borderColor = NSColor.separatorColor.cgColor
        strip.translatesAutoresizingMaskIntoConstraints = false

        let tile = makeStageView()
        (tile as? TileView)?.reloadSettings()
        (tile as? BarContentView)?.reloadSettings()
        tile.translatesAutoresizingMaskIntoConstraints = false
        stageView = tile
        strip.addSubview(tile)

        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: stageSize.width),
            tile.heightAnchor.constraint(equalToConstant: stageSize.height),
            tile.centerXAnchor.constraint(equalTo: strip.centerXAnchor),
            tile.topAnchor.constraint(equalTo: strip.topAnchor, constant: 8),
            tile.bottomAnchor.constraint(equalTo: strip.bottomAnchor, constant: -8),
            strip.widthAnchor.constraint(equalToConstant: 392),
        ])
        return strip
    }

    // MARK: Lifecycle

    override func viewDidAppear() {
        super.viewDidAppear()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.refreshTick() else { return }
            self.stageView.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
    }

    func reloadTile() {
        (stageView as? TileView)?.reloadSettings()
        (stageView as? BarContentView)?.reloadSettings()
        stageView.needsDisplay = true
    }

    // MARK: Controls

    func checkbox(_ title: String, isOn: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = isOn ? .on : .off
        return button
    }

    func labeled(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        return row
    }

    func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

}
