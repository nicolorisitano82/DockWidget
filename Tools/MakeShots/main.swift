import AppKit

// Renders the widgets for the project page. Not mock-ups: the same views the
// Dock draws, on a strip of the same dark glass.

_ = NSApplication.shared
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let backdrop = NSColor(calibratedWhite: 0.13, alpha: 1)

func render(_ view: NSView, scale: CGFloat = 2) -> NSBitmapImageRep? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    backdrop.setFill()
    view.bounds.fill()
    NSGraphicsContext.restoreGraphicsState()
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

func write(_ reps: [(NSBitmapImageRep, NSPoint)], size: NSSize, to name: String) {
    let sheet = NSImage(size: size)
    sheet.lockFocus()
    backdrop.setFill()
    NSRect(origin: .zero, size: size).fill()
    for (rep, origin) in reps {
        rep.draw(in: NSRect(origin: origin, size: rep.size))
    }
    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: output.appendingPathComponent(name))
}

// Clock faces, one of each.
do {
    let side: CGFloat = 180
    var reps: [(NSBitmapImageRep, NSPoint)] = []
    for (index, style) in ClockSettings.Style.allCases.enumerated() {
        SettingsStore.shared.set([
            ClockSettings.Key.style: style.rawValue,
            ClockSettings.Key.showsSeconds: true,
            ClockSettings.Key.showsDate: true,
            ClockSettings.Key.accent: "#FF453A",
        ])
        let view = ClockTileView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.reloadSettings()
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 20
        parts.hour = 10; parts.minute = 9; parts.second = 36
        view.fixedDate = Calendar.current.date(from: parts)
        if let rep = render(view) {
            reps.append((rep, NSPoint(x: CGFloat(index) * side, y: 0)))
        }
    }
    write(reps, size: NSSize(width: side * 5, height: side), to: "clock-faces.png")
}

// Now playing, as a wide bar.
do {
    var state = NowPlayingState()
    state.title = "Giant Steps"
    state.artist = "John Coltrane"
    state.album = "Giant Steps"
    state.isPlaying = true
    state.origin = .mediaRemote
    state.artwork = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
    state.elapsed = 96
    state.duration = 280
    state.elapsedSampledAt = Date()

    SettingsStore.shared.set([NowPlayingSettings.Key.accent: "#32D74B"])
    let view = BarView(frame: NSRect(x: 0, y: 0, width: 4 * 110, height: 140))
    view.tileCount = 4
    view.reloadSettings()
    view.state = state
    if let rep = render(view) {
        write([(rep, .zero)], size: rep.size, to: "now-playing.png")
    }
}

// The actions row.
do {
    ActionsSettings(slots: ActionsSettings.defaults).save()
    let view = ActionsBarView(frame: NSRect(x: 0, y: 0, width: 3 * 110, height: 140))
    view.tileCount = 3
    view.reloadSettings()
    if let rep = render(view) {
        write([(rep, .zero)], size: rep.size, to: "actions.png")
    }
}

// Sensors need two samples before a rate means anything.
SettingsStore.shared.set([
    SensorsSettings.Key.accent: "#0A84FF",
    SensorsSettings.Key.barSensors: "cpu,memory,network,battery",
    SensorsSettings.Key.tileSensor: "cpu",
    SensorsSettings.Key.mode: "tile",
    SensorsSettings.Key.refresh: 1.0,
])
let tile = SensorsTileView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
tile.reloadSettings()
let bar = SensorsBarView(frame: NSRect(x: 0, y: 0, width: 4 * 110, height: 140))
bar.tileCount = 4
bar.reloadSettings()

DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
    if let tileRep = render(tile) {
        write([(tileRep, .zero)], size: tileRep.size, to: "sensors-tile.png")
    }
    if let barRep = render(bar) {
        write([(barRep, .zero)], size: barRep.size, to: "sensors-bar.png")
    }
    exit(0)
}
RunLoop.main.run()
