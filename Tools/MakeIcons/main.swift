import AppKit

// Renders the widget's own artwork into an .iconset, so the app icon in the
// Dock matches the tile that replaces it once the plug-in loads.

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: makeicons <clock|nowplaying|manager> <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let kind = arguments[1]
let outputDirectory = URL(fileURLWithPath: arguments[2])

_ = NSApplication.shared

/// The app's icon when there is a drawing for it on disk.
///
/// The artwork arrives as a squircle sitting on a flat background, so the
/// background is measured from a corner pixel and everything unlike it is
/// taken as the art. What is left is scaled to the 824-of-1024 that macOS
/// expects and clipped to the system's own corner, rather than trusting the
/// corner that came in the picture.
final class SourceIconView: NSView {
    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Art/AppIcon.png")

    static var artwork: NSImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    /// The part of the picture that is not background.
    private static func trimmed(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = source.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return image }
        let width = source.width, height = source.height
        let rowBytes = source.bytesPerRow
        let step = source.bitsPerPixel / 8
        guard step >= 3 else { return image }

        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let offset = y * rowBytes + x * step
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }
        let background = pixel(1, 1)
        func isArt(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = pixel(x, y)
            return abs(r - background.0) + abs(g - background.1) + abs(b - background.2) > 24
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        // Every fourth pixel: the shape is a thousand across and the bounds do
        // not need to be found to the pixel.
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) where isArt(x, y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return image }

        // Square it off around the middle, so nothing is stretched.
        let side = max(maxX - minX, maxY - minY) + 1
        let centreX = (minX + maxX) / 2, centreY = (minY + maxY) / 2
        let box = CGRect(x: max(centreX - side / 2, 0), y: max(centreY - side / 2, 0),
                         width: min(side, width), height: min(side, height))
        guard let cropped = source.cropping(to: box) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: box.width, height: box.height))
    }

    private static let prepared: NSImage? = artwork.map(trimmed)

    override func draw(_ dirtyRect: NSRect) {
        guard let image = Self.prepared else { return }
        let card = TileGeometry.artworkRect(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        TileGeometry.cardPath(in: card).addClip()
        image.draw(in: card, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The manager's own icon: widgets sitting in a dock bar.
final class ManagerIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        let barHeight = side * 0.44
        let bar = NSRect(x: card.minX + side * 0.09, y: card.midY - barHeight / 2,
                         width: side * 0.82, height: barHeight)
        palette.faint.setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight * 0.32, yRadius: barHeight * 0.32).fill()

        let tileSide = barHeight * 0.56
        let gap = tileSide * 0.36
        var x = bar.midX - (tileSide * 3 + gap * 2) / 2
        for index in 0..<3 {
            let box = NSRect(x: x, y: bar.midY - tileSide / 2, width: tileSide, height: tileSide)
            (index == 1 ? palette.accent : palette.primary.withAlphaComponent(0.8)).setFill()
            NSBezierPath(roundedRect: box, xRadius: tileSide * 0.26, yRadius: tileSide * 0.26).fill()
            x += tileSide + gap
        }
    }
}

/// The actions widget's icon: its own cells, two by two.
final class ActionsIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let slots = ActionsSettings.defaults
        let gap = card.width * 0.07
        let side = (card.width * 0.74 - gap) / 2
        let origin = NSPoint(x: card.midX - side - gap / 2, y: card.midY - side - gap / 2)

        for (index, slot) in slots.enumerated() {
            let box = NSRect(x: origin.x + CGFloat(index % 2) * (side + gap),
                             y: origin.y + CGFloat(1 - index / 2) * (side + gap),
                             width: side, height: side)
            let radius = side * 0.28
            slot.background.setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()

            let glyph = box.insetBy(dx: side * 0.26, dy: side * 0.26)
            let configuration = NSImage.SymbolConfiguration(pointSize: glyph.height, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: slot.icon))
            guard let image = NSImage(systemSymbolName: slot.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { continue }
            let size = image.size
            let scale = min(glyph.width / size.width, glyph.height / size.height)
            image.draw(in: NSRect(x: glyph.midX - size.width * scale / 2,
                                  y: glyph.midY - size.height * scale / 2,
                                  width: size.width * scale, height: size.height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
    }
}

/// The note's icon: a page with a coloured tab and a few written lines.
final class NoteIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        NSGraphicsContext.saveGraphicsState()
        TileGeometry.cardPath(in: card).addClip()
        (NSColor(hexString: NoteSettings.current.accentHex) ?? .systemYellow).setFill()
        NSRect(x: card.minX, y: card.minY, width: side * 0.10, height: card.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let widths: [CGFloat] = [0.62, 0.52, 0.42]
        for (index, width) in widths.enumerated() {
            let height = side * 0.075
            let line = NSRect(x: card.minX + side * 0.22,
                              y: card.midY + side * 0.16 - CGFloat(index) * side * 0.20,
                              width: side * width, height: height)
            (index == 0 ? palette.primary : palette.secondary).setFill()
            NSBezierPath(roundedRect: line, xRadius: height / 2, yRadius: height / 2).fill()
        }
    }
}

/// The shelf's icon: a ledge with a couple of things put down on it.
final class ShelfIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        let ledge = NSRect(x: card.minX + side * 0.16, y: card.minY + side * 0.28,
                           width: side * 0.68, height: side * 0.065)
        (NSColor(hexString: ShelfSettings.current("shelf").accentHex) ?? .systemTeal).setFill()
        NSBezierPath(roundedRect: ledge, xRadius: ledge.height / 2,
                     yRadius: ledge.height / 2).fill()

        for (index, width) in [CGFloat(0.20), 0.16, 0.13].enumerated() {
            let height = side * (0.30 - CGFloat(index) * 0.05)
            let box = NSRect(x: ledge.minX + side * 0.04 + CGFloat(index) * side * 0.24,
                             y: ledge.maxY, width: side * width, height: height)
            (index == 0 ? palette.primary : palette.secondary).setFill()
            NSBezierPath(roundedRect: box, xRadius: side * 0.035, yRadius: side * 0.035).fill()
        }
    }
}

/// The calendar's icon: a sheet with a coloured header and a date on it.
final class CalendarIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let palette = self.palette
        let side = card.width

        NSGraphicsContext.saveGraphicsState()
        TileGeometry.cardPath(in: card).addClip()
        (NSColor(hexString: CalendarSettings.current("calendar").accentHex) ?? .systemRed).setFill()
        NSRect(x: card.minX, y: card.maxY - side * 0.26,
               width: card.width, height: side * 0.26).fill()
        NSGraphicsContext.restoreGraphicsState()

        // A grid of days, with today filled in.
        let columns = 4, rows = 3
        let cell = side * 0.13
        let gap = side * 0.055
        let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
        let originX = card.midX - gridWidth / 2
        let originY = card.minY + side * 0.16
        for row in 0..<rows {
            for column in 0..<columns {
                let box = NSRect(x: originX + CGFloat(column) * (cell + gap),
                                 y: originY + CGFloat(rows - 1 - row) * (cell + gap),
                                 width: cell, height: cell)
                let isToday = row == 1 && column == 2
                (isToday ? palette.accent : palette.secondary.withAlphaComponent(0.55)).setFill()
                NSBezierPath(roundedRect: box, xRadius: cell * 0.3, yRadius: cell * 0.3).fill()
            }
        }
    }
}

/// The weather's icon: a sun coming out from behind a cloud.
final class WeatherIconView: TileView {
    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let palette = self.palette
        let side = card.width
        let accent = NSColor(hexString: WeatherSettings.current("weather").accentHex) ?? .systemBlue

        let sun = NSRect(x: card.midX - side * 0.04, y: card.midY - side * 0.02,
                         width: side * 0.34, height: side * 0.34)
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: sun).fill()

        // The cloud: three circles and a base, which is all a cloud ever is.
        let base = NSRect(x: card.minX + side * 0.14, y: card.minY + side * 0.26,
                          width: side * 0.62, height: side * 0.20)
        accent.setFill()
        NSBezierPath(roundedRect: base, xRadius: base.height / 2, yRadius: base.height / 2).fill()
        for (offset, size) in [(CGFloat(0.10), CGFloat(0.22)), (0.30, 0.30), (0.50, 0.20)] {
            let puff = NSRect(x: base.minX + side * offset, y: base.midY,
                              width: side * size, height: side * size)
            NSBezierPath(ovalIn: puff).fill()
        }
        palette.secondary.withAlphaComponent(0).setFill()
    }
}

func makeView(side: CGFloat) -> NSView {
    let frame = NSRect(x: 0, y: 0, width: side, height: side)
    switch kind {
    case "clock":
        let view = ClockTileView(frame: frame)
        view.reloadSettings()
        // The hands at 10:09 leave the face open — the usual choice for clock art.
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 10; components.minute = 9; components.second = 36
        view.fixedDate = Calendar.current.date(from: components)
        return view
    case "actions":
        let view = ActionsIconView(frame: frame)
        view.reloadSettings()
        return view
    case "sensors":
        let view = SensorsTileView(frame: frame)
        view.reloadSettings()
        return view
    case "disks":
        let view = DisksTileView(frame: frame)
        view.reloadSettings()
        return view
    case "applenotes":
        let view = AppleNotesTileView(frame: frame)
        view.reloadSettings()
        return view
    case "note":
        let view = NoteIconView(frame: frame)
        view.reloadSettings()
        return view
    case "folder":
        let view = FolderTileView(frame: frame)
        view.reloadSettings()
        return view
    case "shelf":
        let view = ShelfIconView(frame: frame)
        view.reloadSettings()
        return view
    case "calendar":
        let view = CalendarIconView(frame: frame)
        view.reloadSettings()
        return view
    case "weather":
        let view = WeatherIconView(frame: frame)
        view.reloadSettings()
        return view
    case "manager":
        // The drawn icon is the fallback: a picture in Resources/Art wins.
        if SourceIconView.artwork != nil { return SourceIconView(frame: frame) }
        let view = ManagerIconView(frame: frame)
        view.reloadSettings()
        return view
    default:
        let view = NowPlayingTileView(frame: frame)
        view.reloadSettings()
        return view
    }
}

func renderPNG(side: Int) throws -> Data {
    let view = makeView(side: CGFloat(side))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "makeicons", code: 1)
    }
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "makeicons", code: 2)
    }
    return data
}

let variants: [(name: String, side: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for variant in variants {
    let data = try renderPNG(side: variant.side)
    try data.write(to: outputDirectory.appendingPathComponent("\(variant.name).png"))
}
