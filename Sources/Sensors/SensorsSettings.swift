import AppKit

struct SensorsSettings: Equatable {
    enum Mode: String, CaseIterable {
        case tile, bar
        var label: String { self == .tile ? "Standard" : T("Barra", "Bar") }
    }

    var mode: Mode = .tile
    var tileSensor: SensorID = .cpu
    /// Ordered, and kept even when the bar is too narrow to show them all.
    var barSensors: [SensorID] = [.cpu, .memory, .battery]
    var refresh: TimeInterval = 2
    var showsSparkline = true
    var accentHex = "#0A84FF"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static func mode(_ instance: String) -> String { "\(instance).mode" }
        static func tileSensor(_ instance: String) -> String { "\(instance).tileSensor" }
        static func barSensors(_ instance: String) -> String { "\(instance).barSensors" }
        static func refresh(_ instance: String) -> String { "\(instance).refresh" }
        static func sparkline(_ instance: String) -> String { "\(instance).sparkline" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: SensorsSettings { current("sensors") }

    static func current(_ instance: String) -> SensorsSettings {
        let store = SettingsStore.shared
        let defaults = SensorsSettings()
        let stored = store.string(Key.barSensors(instance), or: "")
            .split(separator: ",")
            .compactMap { SensorID(rawValue: String($0)) }
        return SensorsSettings(
            mode: Mode(rawValue: store.string(Key.mode(instance), or: defaults.mode.rawValue)) ?? defaults.mode,
            tileSensor: SensorID(rawValue: store.string(Key.tileSensor(instance), or: defaults.tileSensor.rawValue))
                ?? defaults.tileSensor,
            barSensors: stored.isEmpty ? defaults.barSensors : stored,
            refresh: store.double(Key.refresh(instance), or: defaults.refresh),
            showsSparkline: store.bool(Key.sparkline(instance), or: defaults.showsSparkline),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "sensors") {
        SettingsStore.shared.set([
            Key.mode(instance): mode.rawValue,
            Key.tileSensor(instance): tileSensor.rawValue,
            Key.barSensors(instance): barSensors.map(\.rawValue).joined(separator: ","),
            Key.refresh(instance): refresh,
            Key.sparkline(instance): showsSparkline,
            Key.accent(instance): accentHex,
        ])
    }

    /// The sensors a bar of `count` tiles shows: the chosen ones in order, and
    /// if the bar is wider than the choice, the sensors not yet used.
    ///
    /// Narrowing the bar hides the tail but never forgets it, so widening it
    /// again brings back exactly what was there.
    func visibleBarSensors(count: Int) -> [SensorID] {
        // A sensor this machine cannot answer for is skipped rather than shown
        // as a dash — but it stays in the stored list, because the same
        // settings may travel to a Mac that does report it.
        let available = SensorID.available
        var visible = Array(barSensors.filter(available.contains).prefix(count))
        for candidate in available where visible.count < count {
            if !visible.contains(candidate) { visible.append(candidate) }
        }
        return visible
    }

    /// The tile falls back the same way when its sensor is not available here.
    var effectiveTileSensor: SensorID {
        SensorID.available.contains(tileSensor) ? tileSensor : (SensorID.available.first ?? .cpu)
    }
}
