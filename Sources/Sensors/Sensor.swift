import Foundation

enum SensorID: String, Codable, CaseIterable {
    case cpu, memory, disk, network, battery, power, thermal
    case cpuPower, gpuPower

    /// The sensors this machine can actually answer for. The per-domain power
    /// counters exist everywhere and move only on some hardware.
    static var available: [SensorID] {
        allCases.filter { id in
            switch id {
            case .cpuPower: return IOReportPower.shared.isAvailable(.cpu)
            case .gpuPower: return IOReportPower.shared.isAvailable(.gpu)
            default: return true
            }
        }
    }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memoria"
        case .disk: return "Disco"
        case .network: return "Rete"
        case .battery: return "Batteria"
        case .power: return "Consumo"
        case .thermal: return "Stato termico"
        case .cpuPower: return "Potenza CPU"
        case .gpuPower: return "Potenza GPU"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        case .battery: return "battery.100"
        case .power: return "bolt.fill"
        case .thermal: return "thermometer.medium"
        case .cpuPower: return "cpu"
        case .gpuPower: return "cpu.fill"
        }
    }
}

/// One sample of one sensor.
struct Reading {
    /// 0…1 where the quantity has a full scale; nil for open-ended ones like
    /// network throughput, which get no ring.
    var fraction: Double?
    /// The number as it is shown: short, because a Dock cell is small.
    var text: String
    /// A second line where there is something worth adding.
    var caption: String?
    /// The number to plot, for sensors whose value has no full scale.
    var raw: Double?

    static let unavailable = Reading(fraction: nil, text: "—", caption: nil)
}

protocol SensorReader {
    var id: SensorID { get }
    /// Called on every tick. Readers that measure a rate keep their own
    /// previous sample.
    mutating func read() -> Reading
}

enum SensorFormat {
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Bytes per second, at Dock-cell length: "1,2 MB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = bytesPerSecond
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = value < 10 && unit > 0 ? 1 : 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(number) \(units[unit])/s"
    }

    static func bytes(_ count: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = count
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = value < 10 && unit > 1 ? 1 : 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(number) \(units[unit])"
    }

    static func watts(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0") W"
    }
}
