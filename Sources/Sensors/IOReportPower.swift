import Foundation

/// Per-domain power, read from the energy counters IOReport exposes.
///
/// IOReport is private, but unlike powermetrics it answers an ordinary process:
/// no root, no privileged helper. What it answers with varies by machine —
/// on this hardware only the GPU counter moves, while the CPU ones sit at zero
/// — so every domain is probed rather than assumed, and a domain that never
/// reports is simply not offered.
final class IOReportPower {
    static let shared = IOReportPower()

    enum Domain: String, CaseIterable {
        case cpu, gpu, ane

        /// The aggregate channel, preferred when the machine publishes it.
        var aggregate: String {
            switch self {
            case .cpu: return "CPU Energy"
            case .gpu: return "GPU Energy"
            case .ane: return "ANE Energy"
            }
        }

        /// The per-rail channels to sum when there is no aggregate.
        func matches(_ name: String) -> Bool {
            switch self {
            case .cpu:
                return name.hasPrefix("ECPU") || name.hasPrefix("PCPU")
                    || name.hasPrefix("EACC") || name.hasPrefix("PACC")
            case .gpu:
                return name.hasPrefix("GPU")
            case .ane:
                return name.hasPrefix("ANE")
            }
        }
    }

    private typealias CopyChannelsInGroup = @convention(c)
        (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscription = @convention(c)
        (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
         UInt64, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias CreateSamples = @convention(c)
        (AnyObject, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c)
        (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias GetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetInteger = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples?
    private let createDelta: CreateDelta?
    private let channelName: GetString?
    private let unitLabel: GetString?
    private let integerValue: GetInteger?

    private var subscription: AnyObject?
    private var subscribedChannels: CFMutableDictionary?

    private var previousSample: CFDictionary?
    private var previousAt = Date.distantPast
    private var watts: [Domain: Double] = [:]
    /// A domain counts as present once it has reported anything above zero:
    /// the channels exist on machines that never fill them in.
    private var seen: Set<Domain> = []

    private init() {
        let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        createSamples = symbol("IOReportCreateSamples", as: CreateSamples.self)
        createDelta = symbol("IOReportCreateSamplesDelta", as: CreateDelta.self)
        channelName = symbol("IOReportChannelGetChannelName", as: GetString.self)
        unitLabel = symbol("IOReportChannelGetUnitLabel", as: GetString.self)
        integerValue = symbol("IOReportSimpleGetIntegerValue", as: GetInteger.self)

        guard let copyChannels = symbol("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let createSubscription = symbol("IOReportCreateSubscription", as: CreateSubscription.self),
              let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { return }

        var subscribed: Unmanaged<CFMutableDictionary>?
        subscription = createSubscription(nil, channels, &subscribed, 0, nil)?.takeRetainedValue()
        subscribedChannels = subscribed?.takeRetainedValue()
    }

    var isLinked: Bool { subscription != nil && subscribedChannels != nil }

    /// Whether this machine has ever reported anything for a domain.
    func isAvailable(_ domain: Domain) -> Bool {
        refreshIfNeeded()
        return seen.contains(domain)
    }

    func watts(for domain: Domain) -> Double? {
        refreshIfNeeded()
        return watts[domain]
    }

    /// One delta per window, however many sensors ask for it.
    private func refreshIfNeeded(minimumInterval: TimeInterval = 0.5) {
        guard isLinked, let createSamples, let createDelta,
              let subscription, let subscribedChannels,
              Date().timeIntervalSince(previousAt) >= minimumInterval else { return }

        guard let sample = createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue() else {
            return
        }
        let now = Date()
        defer {
            previousSample = sample
            previousAt = now
        }
        guard let previousSample,
              let delta = createDelta(previousSample, sample, nil)?.takeRetainedValue() else { return }

        let elapsed = max(now.timeIntervalSince(previousAt), 0.001)
        let channels = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] ?? []

        var joules: [Domain: Double] = [:]
        var aggregates: Set<Domain> = []
        for entry in channels {
            let channel = entry as CFDictionary
            guard let name = channelName?(channel)?.takeUnretainedValue() as String?,
                  let unit = unitLabel?(channel)?.takeUnretainedValue() as String?,
                  let raw = integerValue?(channel, 0), raw > 0,
                  let scale = Self.joulesPerUnit[unit] else { continue }

            let energy = Double(raw) * scale
            for domain in Domain.allCases {
                if name == domain.aggregate {
                    // An aggregate replaces the rails rather than adding to them.
                    joules[domain] = energy
                    aggregates.insert(domain)
                } else if !aggregates.contains(domain), domain.matches(name) {
                    joules[domain, default: 0] += energy
                }
            }
        }

        for (domain, energy) in joules {
            watts[domain] = energy / elapsed
            seen.insert(domain)
        }
    }

    private static let joulesPerUnit: [String: Double] = [
        "nJ": 1e-9, "uJ": 1e-6, "mJ": 1e-3, "J": 1,
    ]
}
