import AppKit

final class ClockSettingsModel {
    let instance: String
    var value: ClockSettings {
        didSet { value.save(instance) }
    }

    init(instance: String) {
        self.instance = instance
        value = .current(instance)
    }
}

final class NowPlayingSettingsModel {
    let instance: String
    var value: NowPlayingSettings {
        didSet { value.save(instance) }
    }

    init(instance: String) {
        self.instance = instance
        value = .current(instance)
    }
}

enum AccentPalette {
    /// Icon colours: the accents plus the two neutrals an icon usually wants.
    static var icons: [(name: String, hex: String)] {
        [(T("Bianco", "White"), "#FFFFFF"), (T("Nero", "Black"), "#1C1C1E")] + swatches
    }

    /// Cell backgrounds: the accents plus a dark neutral.
    static var surfaces: [(name: String, hex: String)] {
        swatches + [(T("Ardesia", "Slate"), "#2C2C2E")]
    }

    static let swatches: [(name: String, hex: String)] = [
        (T("Rosso", "Red"), "#FF453A"),
        (T("Arancione", "Orange"), "#FF9F0A"),
        (T("Giallo", "Yellow"), "#FFD60A"),
        (T("Verde", "Green"), "#32D74B"),
        (T("Blu", "Blue"), "#0A84FF"),
        (T("Viola", "Purple"), "#BF5AF2"),
        (T("Rosa", "Pink"), "#FF375F"),
        (T("Grafite", "Graphite"), "#98989D"),
    ]
}

/// A row of colour dots; the selected one wears a ring.
final class AccentSwatchView: NSView {
    var selectedHex: String {
        didSet { needsDisplay = true }
    }
    var onSelect: ((String) -> Void)?

    private let entries: [(name: String, hex: String)]
    private let diameter: CGFloat = 22
    private let spacing: CGFloat = 12

    init(selectedHex: String, entries: [(name: String, hex: String)] = AccentPalette.swatches) {
        self.selectedHex = selectedHex
        self.entries = entries
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(entries.count)
        return NSSize(width: count * diameter + (count - 1) * spacing, height: diameter + 6)
    }

    private func rect(at index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * (diameter + spacing), y: 3, width: diameter, height: diameter)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, swatch) in entries.enumerated() {
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
        for (index, swatch) in entries.enumerated() where rect(at: index).insetBy(dx: -4, dy: -4).contains(point) {
            selectedHex = swatch.hex
            onSelect?(swatch.hex)
            return
        }
    }
}
