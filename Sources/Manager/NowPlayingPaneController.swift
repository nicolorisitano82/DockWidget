import AppKit

final class NowPlayingPaneController: PaneViewController {
    private let model = NowPlayingSettingsModel()
    private var nowPlayingTile: NowPlayingTileView { tileView as! NowPlayingTileView }
    private var channelLabel: NSTextField?
    private var trackLabel: NSTextField?
    private var lastToken = ""
    private var listenerToken: UUID?
    private var widthRowView: NSView?
    private var widthField: NSTextField?
    private var accessibilityNote: NSTextField?

    override func makeTileView() -> TileView {
        NowPlayingTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard listenerToken == nil else { return }
        listenerToken = NowPlayingSource.shared.addListener { [weak self] state in
            self?.nowPlayingTile.state = state
            self?.updateSourceLabels()
        }
        updateModeControls()
    }

    override func refreshTick() -> Bool {
        let token = nowPlayingTile.state.renderToken()
        guard token != lastToken else { return false }
        lastToken = token
        return true
    }

    override func buildControls(in stack: NSStackView) {
        let mode = NSSegmentedControl(
            labels: NowPlayingSettings.Mode.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        mode.selectedSegment = NowPlayingSettings.Mode.allCases.firstIndex(of: model.value.mode) ?? 0
        stack.addArrangedSubview(labeled("Formato", mode))

        let spec = BarLayout.nowPlaying
        let width = NSStepper()
        width.minValue = Double(spec.minimumSpacers)
        width.maxValue = Double(spec.maximumSpacers)
        width.increment = 1
        width.integerValue = spec.spacerCount
        width.target = self
        width.action = #selector(widthChanged)
        widthField = NSTextField(labelWithString: widthLabel(for: spec.spacerCount))
        let widthRow = NSStackView(views: [width, widthField!])
        widthRow.orientation = .horizontal
        widthRow.spacing = 8
        widthRowView = labeled("Larghezza", widthRow)
        stack.addArrangedSubview(widthRowView!)

        accessibilityNote = NSTextField(wrappingLabelWithString: "")
        accessibilityNote!.font = .systemFont(ofSize: 11)
        accessibilityNote!.textColor = .secondaryLabelColor
        accessibilityNote!.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(accessibilityNote!)

        stack.addArrangedSubview(checkbox("Mostra la copertina", isOn: model.value.showsArtwork,
                                          action: #selector(artworkChanged)))
        stack.addArrangedSubview(checkbox("Mostra l'avanzamento", isOn: model.value.showsProgress,
                                          action: #selector(progressChanged)))
        stack.addArrangedSubview(checkbox("Attenua in pausa", isOn: model.value.dimsWhenPaused,
                                          action: #selector(dimChanged)))

        stack.addArrangedSubview(sectionTitle("Colore"))
        let swatches = AccentSwatchView(selectedHex: model.value.accentHex)
        swatches.onSelect = { [weak self] hex in
            self?.model.value.accentHex = hex
            self?.reloadTile()
        }
        stack.addArrangedSubview(swatches)

        stack.addArrangedSubview(sectionTitle("Sorgente"))
        let channel = NSTextField(labelWithString: "—")
        channel.font = .systemFont(ofSize: 12, weight: .medium)
        channelLabel = channel
        stack.addArrangedSubview(channel)

        let track = NSTextField(labelWithString: "")
        track.font = .systemFont(ofSize: 11)
        track.textColor = .secondaryLabelColor
        trackLabel = track
        stack.addArrangedSubview(track)

        let note = NSTextField(wrappingLabelWithString:
            "MediaRemote risponde solo ai processi di cui il sistema si fida: questa finestra di solito no, la tile nel Dock sì, perché la carica un processo firmato da Apple. Senza MediaRemote restano gli annunci di Music e Spotify: titolo e artista, niente copertina né controlli.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(note)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        model.value.mode = NowPlayingSettings.Mode.allCases[sender.selectedSegment]
        applyMode()
        reloadTile()
    }

    @objc private func widthChanged(_ sender: NSStepper) {
        let spec = BarLayout.nowPlaying
        let count = min(max(sender.integerValue, spec.minimumSpacers), spec.maximumSpacers)
        sender.integerValue = count
        SettingsStore.shared.set(Double(count), for: spec.spacerCountKey)
        widthField?.stringValue = widthLabel(for: count)
        if model.value.mode == .bar { applyMode() }
    }

    private func widthLabel(for count: Int) -> String {
        let spec = BarLayout.nowPlaying
        return count == spec.minimumSpacers ? "\(count) spazi (minimo)" : "\(count) spazi"
    }

    private func applyMode() {
        WidgetInstaller.applyNowPlayingMode(model.value.mode)
        updateModeControls()
    }

    private func updateModeControls() {
        let isBar = model.value.mode == .bar
        widthRowView?.isHidden = !isBar
        guard let note = accessibilityNote else { return }
        if !isBar {
            note.stringValue = ""
            note.isHidden = true
            return
        }
        note.isHidden = false
        note.stringValue = DockAccessibility.isTrusted
            ? "La barra segue le tile vuote nel Dock e cresce con la magnification."
            : "Serve l'accesso Accessibilità: la barra lo chiede al primo avvio, in Impostazioni di Sistema → Privacy e sicurezza → Accessibilità."
    }

    private func updateSourceLabels() {
        let source = NowPlayingSource.shared
        let state = source.state
        if source.mediaRemoteAnswered {
            channelLabel?.stringValue = "MediaRemote — metadati completi"
        } else if state.origin == .broadcast {
            channelLabel?.stringValue = "Annunci Music / Spotify"
        } else {
            channelLabel?.stringValue = "In attesa di un brano"
        }
        if state.hasTrack {
            trackLabel?.stringValue = [state.title, state.artist].compactMap { $0 }.joined(separator: " — ")
        } else {
            trackLabel?.stringValue = "Nessuna riproduzione in corso"
        }
    }

    @objc private func artworkChanged(_ sender: NSButton) {
        model.value.showsArtwork = sender.state == .on
        reloadTile()
    }

    @objc private func progressChanged(_ sender: NSButton) {
        model.value.showsProgress = sender.state == .on
        reloadTile()
    }

    @objc private func dimChanged(_ sender: NSButton) {
        model.value.dimsWhenPaused = sender.state == .on
        reloadTile()
    }
}
