import AppKit
import IOKit
import IOKit.ps

/// Processor load, as the share of ticks that were not idle between two reads.
struct CPUReader: SensorReader {
    let id = SensorID.cpu
    private var previous: (used: Double, total: Double)?

    mutating func read() -> Reading {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return .unavailable }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var used = 0.0
        var total = 0.0
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            used += user + system + nice
            total += user + system + nice + idle
        }

        defer { previous = (used, total) }
        guard let previous, total > previous.total else {
            return Reading(fraction: 0, text: "—", caption: SensorID.cpu.label)
        }
        let fraction = (used - previous.used) / (total - previous.total)
        let clamped = min(max(fraction, 0), 1)
        return Reading(fraction: clamped, text: SensorFormat.percent(clamped), caption: "CPU")
    }
}

/// Memory in use: active, wired and compressed, which is what "pressure"
/// actually follows.
struct MemoryReader: SensorReader {
    let id = SensorID.memory

    mutating func read() -> Reading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .unavailable }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return .unavailable }
        let fraction = min(max(used / total, 0), 1)
        return Reading(fraction: fraction, text: SensorFormat.percent(fraction),
                       caption: SensorFormat.bytes(used))
    }
}

/// Space used on the boot volume.
struct DiskReader: SensorReader {
    let id = SensorID.disk

    mutating func read() -> Reading {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity,
           let free = values.volumeAvailableCapacityForImportantUsage else { return .unavailable }

        let used = Double(total) - Double(free)
        let fraction = min(max(used / Double(total), 0), 1)
        return Reading(fraction: fraction, text: SensorFormat.percent(fraction),
                       caption: "\(SensorFormat.bytes(Double(free))) liberi")
    }
}

/// Throughput across every interface but the loopback, as a rate between reads.
struct NetworkReader: SensorReader {
    let id = SensorID.network
    private var previous: (input: Double, output: Double, at: Date)?

    mutating func read() -> Reading {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return .unavailable }
        defer { freeifaddrs(pointer) }

        var input = 0.0
        var output = 0.0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            input += Double(data.pointee.ifi_ibytes)
            output += Double(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previous = (input, output, now) }
        guard let previous else {
            return Reading(fraction: nil, text: "—", caption: "Rete")
        }
        let elapsed = max(now.timeIntervalSince(previous.at), 0.001)
        let down = max(input - previous.input, 0) / elapsed
        let up = max(output - previous.output, 0) / elapsed
        return Reading(fraction: nil, text: "↓ \(SensorFormat.rate(down))",
                       caption: "↑ \(SensorFormat.rate(up))", raw: down)
    }
}

/// Charge level and whether it is going up or down.
struct BatteryReader: SensorReader {
    let id = SensorID.battery

    mutating func read() -> Reading {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }

            let fraction = min(max(Double(current) / Double(maximum), 0), 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            var caption = charging ? "In carica" : "A batteria"
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0, !charging {
                caption = "\(minutes / 60)h \(minutes % 60)m"
            }
            return Reading(fraction: fraction, text: SensorFormat.percent(fraction), caption: caption)
        }
        return Reading(fraction: nil, text: "—", caption: "Nessuna batteria")
    }
}

/// Power drawn from the battery, from the figures the battery itself reports.
///
/// While charging the current runs the other way and measures the charge, not
/// what the machine is using, so it says so instead of inventing a number.
struct PowerReader: SensorReader {
    let id = SensorID.power

    mutating func read() -> Reading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return .unavailable }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> Int64? {
            guard let value = IORegistryEntryCreateCFProperty(service, key as CFString,
                                                              kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber else { return nil }
            // Amperage arrives as an unsigned 64-bit wrap of a negative value.
            return Int64(bitPattern: value.uint64Value)
        }

        guard let millivolts = number("Voltage"), let milliamps = number("Amperage") else {
            return .unavailable
        }
        let watts = abs(Double(millivolts) * Double(milliamps)) / 1_000_000
        let charging = milliamps > 0
        return Reading(fraction: min(watts / 60, 1),
                       text: SensorFormat.watts(watts),
                       caption: charging ? "in carica" : "assorbiti")
    }
}

/// What the system says about heat, which is the only thermal figure macOS
/// offers without a root helper.
struct ThermalReader: SensorReader {
    let id = SensorID.thermal

    mutating func read() -> Reading {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return Reading(fraction: 0.15, text: "OK", caption: "nominale")
        case .fair: return Reading(fraction: 0.45, text: "Tiepido", caption: "discreto")
        case .serious: return Reading(fraction: 0.75, text: "Caldo", caption: "serio")
        case .critical: return Reading(fraction: 1.0, text: "Critico", caption: "critico")
        @unknown default: return .unavailable
        }
    }
}

/// Power drawn by one part of the chip, from IOReport's energy counters.
struct DomainPowerReader: SensorReader {
    let id: SensorID
    let domain: IOReportPower.Domain
    /// The soft full scale for the ring; the number itself is never clipped.
    let scale: Double

    mutating func read() -> Reading {
        guard let watts = IOReportPower.shared.watts(for: domain) else { return .unavailable }
        return Reading(fraction: min(watts / scale, 1),
                       text: SensorFormat.watts(watts),
                       caption: domain == .cpu ? "CPU" : "GPU",
                       raw: watts)
    }
}
