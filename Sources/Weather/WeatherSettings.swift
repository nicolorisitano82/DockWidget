import AppKit

struct WeatherSettings: Equatable {
    enum Units: String, CaseIterable {
        case celsius, fahrenheit
        var label: String { self == .celsius ? "°C" : "°F" }
        var parameter: String { self == .celsius ? "celsius" : "fahrenheit" }
    }

    /// Empty until a place has been chosen.
    var place = ""
    /// Province and country, so that a Roma is told from the other Romas.
    var region = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var units: Units = .celsius
    var showsRange = true
    var accentHex = "#0A84FF"

    var hasPlace: Bool { !place.isEmpty && !(latitude == 0 && longitude == 0) }
    /// "Roma, Lazio, Italia" when the region is known, "Roma" otherwise.
    var fullPlace: String { region.isEmpty ? place : "\(place), \(region)" }
    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemBlue }

    enum Key {
        static func place(_ instance: String) -> String { "\(instance).place" }
        static func region(_ instance: String) -> String { "\(instance).region" }
        static func latitude(_ instance: String) -> String { "\(instance).latitude" }
        static func longitude(_ instance: String) -> String { "\(instance).longitude" }
        static func units(_ instance: String) -> String { "\(instance).units" }
        static func showsRange(_ instance: String) -> String { "\(instance).showsRange" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: WeatherSettings { current("weather") }

    static func current(_ instance: String) -> WeatherSettings {
        let store = SettingsStore.shared
        let defaults = WeatherSettings()
        return WeatherSettings(
            place: store.string(Key.place(instance), or: defaults.place),
            region: store.string(Key.region(instance), or: defaults.region),
            latitude: store.double(Key.latitude(instance), or: defaults.latitude),
            longitude: store.double(Key.longitude(instance), or: defaults.longitude),
            units: Units(rawValue: store.string(Key.units(instance),
                                                or: defaults.units.rawValue)) ?? defaults.units,
            showsRange: store.bool(Key.showsRange(instance), or: defaults.showsRange),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "weather") {
        SettingsStore.shared.set([
            Key.place(instance): place,
            Key.region(instance): region,
            Key.latitude(instance): latitude,
            Key.longitude(instance): longitude,
            Key.units(instance): units.rawValue,
            Key.showsRange(instance): showsRange,
            Key.accent(instance): accentHex,
        ])
    }
}

/// One hour of the forecast.
struct WeatherHour: Equatable {
    var date: Date
    var temperature: Double
    var code: Int
    var isNight: Bool

    var symbol: String {
        WeatherReading(temperature: temperature, low: temperature, high: temperature,
                       code: code, isNight: isNight, wind: 0, precipitation: 0).symbol
    }

    /// Just the hour, the way the clock is set: "23", or "11PM".
    var label: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

/// What the widget knows about the weather where you are.
struct WeatherReading: Equatable {
    var temperature: Double
    var low: Double
    var high: Double
    var code: Int
    var isNight: Bool
    var wind: Double
    var precipitation: Double
    /// The next few hours, for the strip that fills a wide bar.
    var hours: [WeatherHour] = []

    /// The WMO weather codes, which is what open-meteo answers in.
    var summary: String {
        switch code {
        case 0: return T("Sereno", "Clear")
        case 1: return T("Quasi sereno", "Mostly clear")
        case 2: return T("Parzialmente nuvoloso", "Partly cloudy")
        case 3: return T("Coperto", "Overcast")
        case 45, 48: return T("Nebbia", "Fog")
        case 51, 53, 55: return T("Pioviggine", "Drizzle")
        case 56, 57: return T("Pioviggine gelata", "Freezing drizzle")
        case 61, 63, 65: return T("Pioggia", "Rain")
        case 66, 67: return T("Pioggia gelata", "Freezing rain")
        case 71, 73, 75: return T("Neve", "Snow")
        case 77: return T("Nevischio", "Snow grains")
        case 80, 81, 82: return T("Rovesci", "Showers")
        case 85, 86: return T("Rovesci di neve", "Snow showers")
        case 95: return T("Temporale", "Thunderstorm")
        case 96, 99: return T("Temporale con grandine", "Thunderstorm with hail")
        default: return T("Tempo", "Weather")
        }
    }

    var symbol: String {
        switch code {
        case 0: return isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "snowflake"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }
}

/// A place the search turned up.
struct WeatherPlace: Equatable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double

    var label: String { region.isEmpty ? name : "\(name), \(region)" }
}
