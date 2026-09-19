import AppKit

final class ClockPaneController: PaneViewController {
    private let model = ClockSettingsModel()
    private var clockTile: ClockTileView { tileView as! ClockTileView }
    private var lastToken = Int.min

    override func makeTileView() -> TileView {
        ClockTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func refreshTick() -> Bool {
        let token = clockTile.renderToken()
        guard token != lastToken else { return false }
        lastToken = token
        return true
    }

    override func buildControls(in stack: NSStackView) {
        let style = NSPopUpButton()
        style.addItems(withTitles: ClockSettings.Style.allCases.map(\.label))
        style.selectItem(at: ClockSettings.Style.allCases.firstIndex(of: model.value.style) ?? 0)
        style.target = self
        style.action = #selector(styleChanged)
        stack.addArrangedSubview(labeled("Quadrante", style))

        let format = NSPopUpButton()
        format.addItems(withTitles: ClockSettings.HourFormat.allCases.map(\.label))
        format.selectItem(at: ClockSettings.HourFormat.allCases.firstIndex(of: model.value.hourFormat) ?? 0)
        format.target = self
        format.action = #selector(formatChanged)
        stack.addArrangedSubview(labeled("Formato", format))

        stack.addArrangedSubview(labeled("", checkbox("Mostra i secondi", isOn: model.value.showsSeconds,
                                                      action: #selector(secondsChanged))))
        stack.addArrangedSubview(labeled("", checkbox("Mostra la data", isOn: model.value.showsDate,
                                                      action: #selector(dateChanged))))

        stack.addArrangedSubview(sectionTitle("Colore"))
        let swatches = AccentSwatchView(selectedHex: model.value.accentHex)
        swatches.onSelect = { [weak self] hex in
            self?.model.value.accentHex = hex
            self?.reloadTile()
        }
        stack.addArrangedSubview(swatches)
    }

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        model.value.style = ClockSettings.Style.allCases[sender.indexOfSelectedItem]
        reloadTile()
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        model.value.hourFormat = ClockSettings.HourFormat.allCases[sender.indexOfSelectedItem]
        reloadTile()
    }

    @objc private func secondsChanged(_ sender: NSButton) {
        model.value.showsSeconds = sender.state == .on
        reloadTile()
    }

    @objc private func dateChanged(_ sender: NSButton) {
        model.value.showsDate = sender.state == .on
        reloadTile()
    }
}
