import AppKit

/// The pieces a measurement is drawn with — rings, sparklines, fitted text —
/// shared by every widget that shows a number, so a reading looks the same
/// whichever widget and whichever shape it is in.
enum Gauge {
    static func ring(in rect: NSRect, fraction: Double, width: CGFloat,
                     color: NSColor, track: NSColor) {
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - width / 2

        let background = NSBezierPath()
        background.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        background.lineWidth = width
        track.setStroke()
        background.stroke()

        guard fraction > 0.001 else { return }
        let path = NSBezierPath()
        path.appendArc(withCenter: centre, radius: radius, startAngle: 90,
                       endAngle: 90 - 360 * min(fraction, 1), clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// A line through the recent samples, scaled to the tallest one in view:
    /// throughput has no ceiling, so the shape is the information.
    static func sparkline(in rect: NSRect, samples: [Double], color: NSColor) {
        guard samples.count > 1 else { return }
        let highest = max(samples.max() ?? 1, 0.0001)
        let step = rect.width / CGFloat(samples.count - 1)

        let path = NSBezierPath()
        for (index, sample) in samples.enumerated() {
            let point = NSPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.minY + rect.height * CGFloat(min(sample / highest, 1)))
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.lineWidth = max(1, rect.height * 0.14)
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    static func symbol(_ name: String, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        guard let image else { return }
        let size = image.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        image.draw(in: NSRect(x: rect.midX - size.width * scale / 2,
                              y: rect.midY - size.height * scale / 2,
                              width: size.width * scale, height: size.height * scale),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func text(_ string: String, in rect: NSRect, weight: NSFont.Weight,
                     color: NSColor, maximumSize: CGFloat) {
        let text = string as NSString
        var font = NSFont.roundedSystemFont(ofSize: maximumSize, weight: weight)
        var width = text.size(withAttributes: [.font: font]).width
        var attempts = 0
        while width > rect.width, font.pointSize > 4, attempts < 20 {
            font = NSFont.roundedSystemFont(ofSize: font.pointSize * min(0.92, rect.width / width),
                                            weight: weight)
            width = text.size(withAttributes: [.font: font]).width
            attempts += 1
        }
        text.drawCentered(in: rect, attributes: [.font: font, .foregroundColor: color])
    }

    static func trackColor() -> NSColor {
        NSColor(calibratedWhite: SystemAppearance.shared.isDark ? 1 : 0, alpha: 0.13)
    }
}
