import AppKit
import CoreImage

/// Recolours a folder and stamps a symbol on it, the way macOS 26 lets you
/// customise one in the Finder.
///
/// The colour is a hue rotation rather than a flat fill: the folder keeps its
/// own shading and its edge, and only changes colour — filling it would give
/// back a coloured rectangle in the shape of a folder.
enum FolderIconRenderer {
    /// The hue of the stock folder, measured once: everything rotates from here.
    private static let baseHue: CGFloat = 0.575

    static func icon(for url: URL?, tintHex: String, symbol: String) -> NSImage {
        let base: NSImage = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .folder)

        var image = base
        if let tint = NSColor(hexString: tintHex)?.usingColorSpace(.deviceRGB) {
            image = rotated(base, towards: tint) ?? base
        }
        guard !symbol.isEmpty else { return image }
        return stamped(image, symbol: symbol)
    }

    private static func rotated(_ image: NSImage, towards tint: NSColor) -> NSImage? {
        guard let data = image.tiffRepresentation, let source = CIImage(data: data),
              let filter = CIFilter(name: "CIHueAdjust") else { return nil }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue((hue - baseHue) * 2 * .pi, forKey: kCIInputAngleKey)
        guard var output = filter.outputImage else { return nil }

        // Rotating the hue keeps the stock folder's own saturation, so a
        // vivid red comes back as salmon. The saturation follows the colour
        // that was asked for — and a grey one drains it entirely.
        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(output, forKey: kCIInputImageKey)
            controls.setValue(saturation < 0.12 ? 0 : min(max(saturation * 1.7, 0.7), 2.0),
                              forKey: kCIInputSaturationKey)
            output = controls.outputImage ?? output
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(NSCIImageRep(ciImage: output))
        return result
    }

    private static func stamped(_ image: NSImage, symbol: String) -> NSImage {
        let size = image.size
        let stamped = NSImage(size: size)
        stamped.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))

        // Low on the folder's face and a touch translucent, the way the
        // system's own glyphs sit under the flap rather than on top of it.
        let side = min(size.width, size.height) * 0.34
        let box = NSRect(x: size.width / 2 - side / 2,
                         y: size.height * 0.40 - side / 2,
                         width: side, height: side)
        let configuration = NSImage.SymbolConfiguration(pointSize: side, weight: .medium)
            .applying(NSImage.SymbolConfiguration(
                hierarchicalColor: NSColor(calibratedWhite: 1, alpha: 0.82)))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let glyphSize = glyph.size
            let scale = min(box.width / glyphSize.width, box.height / glyphSize.height)
            glyph.draw(in: NSRect(x: box.midX - glyphSize.width * scale / 2,
                                  y: box.midY - glyphSize.height * scale / 2,
                                  width: glyphSize.width * scale, height: glyphSize.height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        stamped.unlockFocus()
        return stamped
    }
}
