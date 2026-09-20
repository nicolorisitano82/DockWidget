import Foundation

/// Reads the sensors somebody is actually looking at, on one shared beat.
///
/// Both the Dock plug-in and the overlay agent use this: these readings come
/// from public APIs that answer any process, so unlike now playing there is no
/// privileged reader to relay them.
final class SensorSampler {
    static let shared = SensorSampler()

    static let historyLength = 32

    private(set) var readings: [SensorID: Reading] = [:]
    private(set) var history: [SensorID: [Double]] = [:]

    private var readers: [SensorID: SensorReader] = [
        .cpu: CPUReader(), .memory: MemoryReader(), .disk: DiskReader(),
        .network: NetworkReader(), .battery: BatteryReader(),
        .power: PowerReader(), .thermal: ThermalReader(),
        .cpuPower: DomainPowerReader(id: .cpuPower, domain: .cpu, scale: 20),
        .gpuPower: DomainPowerReader(id: .gpuPower, domain: .gpu, scale: 20),
    ]
    private var listeners: [UUID: (ids: Set<SensorID>, handler: () -> Void)] = [:]
    private var timer: Timer?
    private var interval: TimeInterval = 2

    @discardableResult
    func addListener(for ids: Set<SensorID>, handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        listeners[token] = (ids, handler)
        restart()
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        if listeners.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    func setInterval(_ seconds: TimeInterval) {
        let clamped = min(max(seconds, 1), 10)
        guard clamped != interval else { return }
        interval = clamped
        restart()
    }

    func reading(_ id: SensorID) -> Reading {
        readings[id] ?? .unavailable
    }

    func trend(_ id: SensorID) -> [Double] {
        history[id] ?? []
    }

    private func restart() {
        timer?.invalidate()
        guard !listeners.isEmpty else { return }
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        // Only what somebody is showing: a reader that nobody watches costs
        // nothing here.
        let wanted = listeners.values.reduce(into: Set<SensorID>()) { $0.formUnion($1.ids) }
        for id in wanted {
            guard var reader = readers[id] else { continue }
            let reading = reader.read()
            readers[id] = reader
            readings[id] = reading

            if let value = reading.raw ?? reading.fraction {
                var samples = history[id] ?? []
                samples.append(value)
                if samples.count > Self.historyLength {
                    samples.removeFirst(samples.count - Self.historyLength)
                }
                history[id] = samples
            }
        }
        listeners.values.forEach { $0.handler() }
    }
}
