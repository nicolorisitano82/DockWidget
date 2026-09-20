import AppKit

final class NotePaneController: PaneViewController, NSTextViewDelegate {
    init(instance: String) {
        super.init(nibName: nil, bundle: nil)
        self.instance = instance
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("panes are only ever built in code") }

    private lazy var settings = NoteSettings.current(instance)
    private var textView: NSTextView?
    private var observer: NSObjectProtocol?

    override func makeStageView() -> NSView {
        let view = NoteBarView(frame: NSRect(x: 0, y: 0, width: 220, height: 88))
        view.instance = instance
        view.tileCount = BarLayout.note.spacerCount + 1
        return view
    }

    override var stageSize: NSSize { NSSize(width: 220, height: 88) }
    override func refreshTick() -> Bool { false }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard observer == nil else { return }
        // The note can also be written from the Dock, so this window follows.
        observer = SettingsStore.shared.observeChanges { [weak self] in
            guard let self else { return }
            let stored = NoteSettings.current(instance).text
            if self.textView?.string != stored { self.textView?.string = stored }
            self.reloadTile()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    override func buildControls(in stack: NSStackView) {
        let spec = BarLayout.note
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

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 392).isActive = true

        let text = NSTextView()
        text.string = settings.text
        text.font = .systemFont(ofSize: 13)
        text.isRichText = false
        text.delegate = self
        text.autoresizingMask = [.width]
        scroll.documentView = text
        textView = text
        stack.addArrangedSubview(scroll)

        stack.addArrangedSubview(sectionTitle(T("Colore", "Colour")))
        let swatches = AccentSwatchView(selectedHex: settings.accentHex)
        swatches.onSelect = { [weak self] hex in
            guard let self else { return }
            self.settings.accentHex = hex
            self.settings.save(instance)
            self.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        let hint = NSTextField(wrappingLabelWithString: T(
            "Un click sull'appunto nel Dock apre lo stesso testo in un pannello, sopra la barra.",
            "Clicking the note in the Dock opens the same text in a panel above the bar."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(hint)
    }

    private var widthField: NSTextField?

    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        settings.text = textView.string
        settings.save(instance)
        reloadTile()
    }

    @objc private func widthChanged(_ sender: NSStepper) {
        let spec = BarLayout.note
        let count = min(max(sender.integerValue, spec.minimumSpacers), spec.maximumSpacers)
        sender.integerValue = count
        SettingsStore.shared.set(Double(count), for: spec.spacerCountKey)
        widthField?.stringValue = T("\(count + 1) tile", "\(count + 1) tiles")
        WidgetInstaller.applyBarMode(for: "note")
        reloadTile()
    }
}
