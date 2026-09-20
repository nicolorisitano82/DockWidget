import AppKit

/// Editor for the four cells of the actions widget: one cell at a time, so the
/// pane stays the size of the others.
final class ActionsPaneController: PaneViewController {
    private var settings = ActionsSettings.current
    private var selected = 0

    private var symbolButton: NSPopUpButton?
    private var iconSwatches: AccentSwatchView?
    private var cellSwatches: AccentSwatchView?
    private var kindButton: NSPopUpButton?
    private var parameterRow: NSStackView?
    private var parameterLabel: NSTextField?
    private var parameterField: NSTextField?
    private var parameterButton: NSButton?
    private var parameterChoice: NSPopUpButton?

    private var slot: ActionSlot {
        get { settings.slots[selected] }
        set {
            settings.slots[selected] = newValue
            settings.save()
            reloadTile()
        }
    }

    override func makeStageView() -> NSView {
        let view = ActionsBarView(frame: NSRect(x: 0, y: 0, width: 176, height: 88))
        view.tileCount = BarLayout.actions.spacerCount + 1
        return view
    }

    override var stageSize: NSSize { NSSize(width: 176, height: 88) }
    override func refreshTick() -> Bool { false }

    override func buildControls(in stack: NSStackView) {
        let cell = NSSegmentedControl(labels: (1...ActionsSettings.slotCount).map(String.init),
                                      trackingMode: .selectOne,
                                      target: self, action: #selector(cellChanged))
        cell.selectedSegment = 0
        stack.addArrangedSubview(labeled(T("Cella", "Cell"), cell))

        let symbols = NSPopUpButton()
        for name in ActionSymbols.all {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            symbols.menu?.addItem(item)
        }
        symbols.target = self
        symbols.action = #selector(symbolChanged)
        symbolButton = symbols
        stack.addArrangedSubview(labeled("Icona", symbols))

        let iconColours = AccentSwatchView(selectedHex: slot.iconHex, entries: AccentPalette.icons)
        iconColours.onSelect = { [weak self] hex in
            guard let self else { return }
            self.slot.iconHex = hex
        }
        iconSwatches = iconColours
        stack.addArrangedSubview(labeled(T("Colore icona", "Icon colour"), iconColours))

        let cellColours = AccentSwatchView(selectedHex: slot.backgroundHex, entries: AccentPalette.surfaces)
        cellColours.onSelect = { [weak self] hex in
            guard let self else { return }
            self.slot.backgroundHex = hex
        }
        cellSwatches = cellColours
        stack.addArrangedSubview(labeled(T("Colore cella", "Cell colour"), cellColours))

        let kinds = NSPopUpButton()
        kinds.addItems(withTitles: [T("Nessuna", "None"), T("Apri un'app", "Open an app"), T("Apri un indirizzo o un file", "Open an address or a file"),
                                    T("Scorciatoia", "Shortcut"), T("Azione di sistema", "System action")])
        kinds.target = self
        kinds.action = #selector(kindChanged)
        kindButton = kinds
        stack.addArrangedSubview(labeled(T("Azione", "Action"), kinds))

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        parameterLabel = label

        let field = NSTextField()
        field.placeholderString = T("esempio.com oppure ~/Documenti", "example.com or ~/Documents")
        field.target = self
        field.action = #selector(parameterFieldChanged)
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        parameterField = field

        let button = NSButton(title: T("Scegli…", "Choose…"), target: self, action: #selector(chooseApp))
        parameterButton = button

        let choice = NSPopUpButton()
        choice.target = self
        choice.action = #selector(parameterChoiceChanged)
        parameterChoice = choice

        let row = NSStackView(views: [field, button, choice, label])
        row.orientation = .horizontal
        row.spacing = 8
        parameterRow = row
        stack.addArrangedSubview(labeled("", row))

        loadSlotIntoControls()
    }

    // MARK: Controls

    private func loadSlotIntoControls() {
        symbolButton?.selectItem(withTitle: slot.symbol)
        iconSwatches?.selectedHex = slot.iconHex
        cellSwatches?.selectedHex = slot.backgroundHex
        kindButton?.selectItem(at: kindIndex(of: slot.kind))
        updateParameterControls()
    }

    private func kindIndex(of kind: ActionKind) -> Int {
        switch kind {
        case .none: return 0
        case .app: return 1
        case .open: return 2
        case .shortcut: return 3
        case .system: return 4
        }
    }

    private func updateParameterControls() {
        let field = parameterField
        let button = parameterButton
        let choice = parameterChoice
        [field, button, choice].forEach { $0?.isHidden = true }
        parameterLabel?.stringValue = ""

        switch slot.kind {
        case .none:
            parameterLabel?.stringValue = T("La cella resta vuota.", "The cell stays empty.")
        case .app(let path):
            button?.isHidden = false
            parameterLabel?.stringValue = path.isEmpty
                ? T("Nessuna app scelta", "No app chosen")
                : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case .open(let target):
            field?.isHidden = false
            field?.stringValue = target
        case .shortcut(let name):
            choice?.isHidden = false
            let names = ShortcutsCatalog.names()
            choice?.removeAllItems()
            if names.isEmpty {
                choice?.addItem(withTitle: T("Nessuna scorciatoia", "No shortcuts"))
                parameterLabel?.stringValue = T("Crea una scorciatoia nell'app Comandi rapidi.", "Create one in the Shortcuts app.")
            } else {
                choice?.addItems(withTitles: names)
                choice?.selectItem(withTitle: name)
            }
        case .system(let action):
            choice?.isHidden = false
            choice?.removeAllItems()
            choice?.addItems(withTitles: SystemAction.allCases.map(\.label))
            choice?.selectItem(at: SystemAction.allCases.firstIndex(of: action) ?? 0)
        }
    }

    @objc private func cellChanged(_ sender: NSSegmentedControl) {
        selected = sender.selectedSegment
        loadSlotIntoControls()
    }

    @objc private func symbolChanged(_ sender: NSPopUpButton) {
        slot.symbol = sender.titleOfSelectedItem ?? slot.symbol
    }

    @objc private func kindChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: slot.kind = .app(path: "")
        case 2: slot.kind = .open(target: "")
        case 3: slot.kind = .shortcut(name: ShortcutsCatalog.names().first ?? "")
        case 4: slot.kind = .system(.lockScreen)
        default: slot.kind = .none
        }
        updateParameterControls()
    }

    @objc private func parameterFieldChanged(_ sender: NSTextField) {
        slot.kind = .open(target: sender.stringValue)
    }

    @objc private func parameterChoiceChanged(_ sender: NSPopUpButton) {
        switch slot.kind {
        case .shortcut:
            slot.kind = .shortcut(name: sender.titleOfSelectedItem ?? "")
        case .system:
            let action = SystemAction.allCases[max(0, sender.indexOfSelectedItem)]
            slot.kind = .system(action)
            if slot.symbol == ActionSlot.empty.symbol { slot.symbol = "bolt.fill" }
        default:
            break
        }
        updateParameterControls()
    }

    @objc private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        slot.kind = .app(path: url.path)
        updateParameterControls()
    }
}

/// The user's Shortcuts, read from the command line tool that ships with macOS.
enum ShortcutsCatalog {
    private static var cached: [String]?

    static func names() -> [String] {
        if let cached { return cached }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let names = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        cached = names
        return names
    }
}
