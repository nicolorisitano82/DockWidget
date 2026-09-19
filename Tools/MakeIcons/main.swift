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
    case "manager":
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
