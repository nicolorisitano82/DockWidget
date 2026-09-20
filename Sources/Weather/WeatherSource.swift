import AppKit

/// Fetches the weather for one widget's place.
///
/// Open-Meteo, because it answers without a key, without an account and without
/// a licence that a project like this one could not honour. One store per copy,
/// so two weather widgets can watch two cities.
final class WeatherStore {
    private static var stores: [String: WeatherStore] = [:]

    static func shared(_ instance: String) -> WeatherStore {
        if let existing = stores[instance] { return existing }
        let store = WeatherStore(instance: instance)
        stores[instance] = store
        return store
    }

    let instance: String
    private(set) var reading: WeatherReading?
    private(set) var problem: String?

    private var listeners: [UUID: () -> Void] = [:]
    private var timer: Timer?
    private var fetching = false
    private var lastPlace = ""

    private init(instance: String) {
        self.instance = instance
    }

    var settings: WeatherSettings { .current(instance) }

    @discardableResult
    func addListener(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = handler
        start()
        handler()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        // A quarter of an hour. The forecast is not published faster than that,
        // and somebody's Dock is not a reason to hammer a free service.
        let ticker = Timer(timeInterval: 900, repeats: true) { [weak self] _ in self?.reload() }
        ticker.tolerance = 60
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        reload()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the settings change: the place may be somewhere else now.
    func refresh() {
        let place = "\(settings.place)|\(settings.latitude)|\(settings.longitude)|\(settings.units.rawValue)"
        guard place != lastPlace else { return }
        lastPlace = place
        reading = nil
        reload()
    }

    private func reload() {
        let settings = self.settings
        guard settings.hasPlace else {
            publish(nil, problem: T("Scegli un posto.", "Pick a place."))
            return
        }
        guard !fetching else { return }
        fetching = true

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", settings.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", settings.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m,precipitation"),
            URLQueryItem(name: "daily", value: "temperature_2m_min,temperature_2m_max"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: settings.units.parameter),
            URLQueryItem(name: "timezone", value: "auto"),
            // Two days, because "the next six hours" crosses midnight for a
            // good part of every evening.
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let url = components.url else {
            fetching = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                if let error {
                    Diagnostics.once("weather-fetch",
                                     "meteo non raggiungibile: \(error.localizedDescription)")
                    self.publish(self.reading,
                                 problem: T("Nessuna risposta.", "No answer."))
                    return
                }
                guard let data, let reading = Self.decode(data) else {
                    self.publish(self.reading, problem: T("Risposta illeggibile.", "Unreadable answer."))
                    return
                }
                self.publish(reading, problem: nil)
            }
        }.resume()
    }

    private static func decode(_ data: Data) -> WeatherReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double
        else { return nil }
        let daily = root["daily"] as? [String: Any]
        let lows = daily?["temperature_2m_min"] as? [Double] ?? []
        let highs = daily?["temperature_2m_max"] as? [Double] ?? []
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        return WeatherReading(
            temperature: temperature,
            low: lows.first ?? temperature,
            high: highs.first ?? temperature,
            code: current["weather_code"] as? Int ?? 0,
            isNight: !isDay,
            wind: current["wind_speed_10m"] as? Double ?? 0,
            precipitation: current["precipitation"] as? Double ?? 0,
            hours: hours(from: root["hourly"] as? [String: Any])
        )
    }

    /// The hours still to come, at most eight of them.
    ///
    /// open-meteo answers in the place's own zone with no offset on the
    /// stamps, so they are read back in that zone rather than in this Mac's.
    private static func hours(from hourly: [String: Any]?) -> [WeatherHour] {
        guard let hourly,
              let stamps = hourly["time"] as? [String],
              let temperatures = hourly["temperature_2m"] as? [Double]
        else { return [] }
        let codes = hourly["weather_code"] as? [Int] ?? []
        let days = hourly["is_day"] as? [Int] ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = .autoupdatingCurrent

        let now = Date().addingTimeInterval(-1_800)
        var found: [WeatherHour] = []
        for (index, stamp) in stamps.enumerated() where index < temperatures.count {
            guard let when = formatter.date(from: stamp), when >= now else { continue }
            found.append(WeatherHour(date: when,
                                     temperature: temperatures[index],
                                     code: index < codes.count ? codes[index] : 0,
                                     isNight: index < days.count ? days[index] == 0 : false))
            if found.count == 8 { break }
        }
        return found
    }

    private func publish(_ reading: WeatherReading?, problem: String?) {
        guard reading != self.reading || problem != self.problem else { return }
        self.reading = reading
        self.problem = problem
        listeners.values.forEach { $0() }
    }

    // MARK: Finding a place

    /// Open-Meteo's own geocoder, so choosing a city needs no second service.
    static func search(_ text: String, completion: @escaping ([WeatherPlace]) -> Void) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            completion([])
            return
        }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else {
            completion([])
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var found: [WeatherPlace] = []
            if let data,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = root["results"] as? [[String: Any]] {
                found = results.compactMap { entry in
                    guard let name = entry["name"] as? String,
                          let latitude = entry["latitude"] as? Double,
                          let longitude = entry["longitude"] as? Double
                    else { return nil }
                    let region = [entry["admin1"] as? String, entry["country"] as? String]
                        .compactMap { $0 }.joined(separator: ", ")
                    return WeatherPlace(name: name, region: region,
                                        latitude: latitude, longitude: longitude)
                }
            }
            DispatchQueue.main.async { completion(found) }
        }.resume()
    }
}
