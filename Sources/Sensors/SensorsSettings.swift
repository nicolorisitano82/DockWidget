import AppKit

struct SensorsSettings: Equatable {
    enum Mode: String, CaseIterable {
        case tile, bar
        var label: String { self == .tile ? "Standard" : "Barra" }
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
        static let mode = "sensors.mode"
        static let tileSensor = "sensors.tileSensor"
        static let barSensors = "sensors.barSensors"
        static let refresh = "sensors.refresh"
        static let sparkline = "sensors.sparkline"
        static let accent = "sensors.accent"
    }

    static var current: SensorsSettings {
        let store = SettingsStore.shared
        let defaults = SensorsSettings()
        let stored = store.string(Key.barSensors, or: "")
            .split(separator: ",")
            .compactMap { SensorID(rawValue: String($0)) }
        return SensorsSettings(
            mode: Mode(rawValue: store.string(Key.mode, or: defaults.mode.rawValue)) ?? defaults.mode,
            tileSensor: SensorID(rawValue: store.string(Key.tileSensor, or: defaults.tileSensor.rawValue))
                ?? defaults.tileSensor,
            barSensors: stored.isEmpty ? defaults.barSensors : stored,
            refresh: store.double(Key.refresh, or: defaults.refresh),
            showsSparkline: store.bool(Key.sparkline, or: defaults.showsSparkline),
            accentHex: store.string(Key.accent, or: defaults.accentHex)
        )
    }

    func save() {
        SettingsStore.shared.set([
            Key.mode: mode.rawValue,
            Key.tileSensor: tileSensor.rawValue,
            Key.barSensors: barSensors.map(\.rawValue).joined(separator: ","),
            Key.refresh: refresh,
            Key.sparkline: showsSparkline,
            Key.accent: accentHex,
        ])
    }

    /// The sensors a bar of `count` tiles shows: the chosen ones in order, and
    /// if the bar is wider than the choice, the sensors not yet used.
    ///
    /// Narrowing the bar hides the tail but never forgets it, so widening it
    /// again brings back exactly what was there.
    func visibleBarSensors(count: Int) -> [SensorID] {
        var visible = Array(barSensors.prefix(count))
        for candidate in SensorID.available where visible.count < count {
            if !visible.contains(candidate) { visible.append(candidate) }
        }
        return visible
    }
}
