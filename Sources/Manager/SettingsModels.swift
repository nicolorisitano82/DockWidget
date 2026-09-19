import AppKit

final class ClockSettingsModel {
    var value: ClockSettings = .current {
        didSet { persist() }
    }

    private func persist() {
        SettingsStore.shared.set([
            ClockSettings.Key.style: value.style.rawValue,
            ClockSettings.Key.hourFormat: value.hourFormat.rawValue,
            ClockSettings.Key.showsSeconds: value.showsSeconds,
            ClockSettings.Key.showsDate: value.showsDate,
            ClockSettings.Key.accent: value.accentHex,
        ])
    }
}

final class NowPlayingSettingsModel {
    var value: NowPlayingSettings = .current {
        didSet { persist() }
    }

    private func persist() {
        SettingsStore.shared.set([
            NowPlayingSettings.Key.mode: value.mode.rawValue,
            NowPlayingSettings.Key.showsArtwork: value.showsArtwork,
            NowPlayingSettings.Key.showsProgress: value.showsProgress,
            NowPlayingSettings.Key.dimsWhenPaused: value.dimsWhenPaused,
            NowPlayingSettings.Key.accent: value.accentHex,
        ])
    }
}

enum AccentPalette {
    static let swatches: [(name: String, hex: String)] = [
        ("Rosso", "#FF453A"),
        ("Arancione", "#FF9F0A"),
        ("Giallo", "#FFD60A"),
        ("Verde", "#32D74B"),
        ("Blu", "#0A84FF"),
        ("Viola", "#BF5AF2"),
        ("Rosa", "#FF375F"),
        ("Grafite", "#98989D"),
    ]
}

/// A row of colour dots; the selected one wears a ring.
final class AccentSwatchView: NSView {
    var selectedHex: String {
        didSet { needsDisplay = true }
    }
    var onSelect: ((String) -> Void)?

    private let diameter: CGFloat = 22
    private let spacing: CGFloat = 12

    init(selectedHex: String) {
        self.selectedHex = selectedHex
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(AccentPalette.swatches.count)
        return NSSize(width: count * diameter + (count - 1) * spacing, height: diameter + 6)
    }

    private func rect(at index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * (diameter + spacing), y: 3, width: diameter, height: diameter)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, swatch) in AccentPalette.swatches.enumerated() {
            let box = rect(at: index)
            let color = NSColor(hexString: swatch.hex) ?? .systemBlue
            color.setFill()
            NSBezierPath(ovalIn: box.insetBy(dx: 2, dy: 2)).fill()
            if swatch.hex == selectedHex {
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                let ring = NSBezierPath(ovalIn: box.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, swatch) in AccentPalette.swatches.enumerated() where rect(at: index).insetBy(dx: -4, dy: -4).contains(point) {
            selectedHex = swatch.hex
            onSelect?(swatch.hex)
            return
        }
    }
}
