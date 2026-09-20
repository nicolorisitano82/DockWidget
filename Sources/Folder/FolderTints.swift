import AppKit

/// The colours a folder can take, and the dots that stand for them in a menu.
enum FolderTints {
    static let all: [(label: String, hex: String)] = [
        (T("Originale", "As in the Finder"), ""),
        (T("Rosso", "Red"), "#FF453A"),
        (T("Arancione", "Orange"), "#FF9F0A"),
        (T("Giallo", "Yellow"), "#FFD60A"),
        (T("Verde", "Green"), "#32D74B"),
        (T("Acqua", "Teal"), "#40C8E0"),
        (T("Blu", "Blue"), "#0A84FF"),
        (T("Viola", "Purple"), "#BF5AF2"),
        (T("Rosa", "Pink"), "#FF375F"),
        (T("Grigio", "Grey"), "#98989D"),
    ]

    static func swatch(_ hex: String) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        let box = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        if let colour = NSColor(hexString: hex) {
            colour.setFill()
            NSBezierPath(ovalIn: box).fill()
        } else {
            // "As in the Finder": an outline, since there is no colour to show.
            NSColor.tertiaryLabelColor.setStroke()
            let ring = NSBezierPath(ovalIn: box.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1.2
            ring.stroke()
        }
        image.unlockFocus()
        return image
    }
}
