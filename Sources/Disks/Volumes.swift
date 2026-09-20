import AppKit

/// A mounted volume, with the numbers a widget needs and nothing else.
struct VolumeInfo: Equatable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let isRemovable: Bool
    let isInternal: Bool

    var used: Int64 { max(total - free, 0) }
    var fraction: Double { total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0 }
    var isBoot: Bool { url.path == "/" }

    var symbol: String {
        if isBoot { return "internaldrive.fill" }
        return isRemovable || !isInternal ? "externaldrive.fill" : "internaldrive"
    }
}

/// Lists what is mounted, and says when that changes.
///
/// Volumes come and go while the widget is on screen, so this watches the
/// workspace rather than polling: plugging a drive in should light a cell up,
/// not wait for the next tick.
final class VolumeScanner {
    static let shared = VolumeScanner()

    private(set) var volumes: [VolumeInfo] = []
    private var listeners: [UUID: () -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsBrowsableKey,
    ]

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
        guard observers.isEmpty else { return }
        scan()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.scan() }
            observers.append(token)
        }
        // Free space moves on its own; the list does not.
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.scan() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var found: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.volumeIsBrowsable ?? true,
                  let total = values.volumeTotalCapacity, total > 0,
                  let free = values.volumeAvailableCapacity else { continue }
            found.append(VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                total: Int64(total),
                free: Int64(free),
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? true
            ))
        }

        // The boot volume first, then externals, then the rest: the order a
        // person expects to read them in.
        found.sort { lhs, rhs in
            if lhs.isBoot != rhs.isBoot { return lhs.isBoot }
            if lhs.isInternal != rhs.isInternal { return !lhs.isInternal }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        guard found != volumes else { return }
        volumes = found
        listeners.values.forEach { $0() }
    }

    func volume(named name: String) -> VolumeInfo? {
        volumes.first { $0.name == name } ?? volumes.first
    }

    func eject(_ volume: VolumeInfo) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            scan()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

struct DisksSettings: Equatable {
    enum Mode: String, CaseIterable {
        case tile, bar
        var label: String { self == .tile ? T("Standard", "Standard") : T("Barra", "Bar") }
    }

    var mode: Mode = .tile
    /// Empty means the boot volume.
    var tileVolume: String = ""
    var showsFree = true
    var accentHex = "#32D74B"

    var accent: NSColor { NSColor(hexString: accentHex) ?? .systemGreen }

    enum Key {
        static func mode(_ instance: String) -> String { "\(instance).mode" }
        static func tileVolume(_ instance: String) -> String { "\(instance).tileVolume" }
        static func showsFree(_ instance: String) -> String { "\(instance).showsFree" }
        static func accent(_ instance: String) -> String { "\(instance).accent" }
    }

    static var current: DisksSettings { current("disks") }

    static func current(_ instance: String) -> DisksSettings {
        let store = SettingsStore.shared
        let defaults = DisksSettings()
        return DisksSettings(
            // In the notch there is no room for a square tile, so the shape is
            // not a choice: it is always the bar.
            mode: WidgetInstance.isNotch(instance)
                ? .bar
                : Mode(rawValue: store.string(Key.mode(instance), or: defaults.mode.rawValue))
                    ?? defaults.mode,
            tileVolume: store.string(Key.tileVolume(instance), or: defaults.tileVolume),
            showsFree: store.bool(Key.showsFree(instance), or: defaults.showsFree),
            accentHex: store.string(Key.accent(instance), or: defaults.accentHex)
        )
    }

    func save(_ instance: String = "disks") {
        SettingsStore.shared.set([
            Key.mode(instance): mode.rawValue,
            Key.tileVolume(instance): tileVolume,
            Key.showsFree(instance): showsFree,
            Key.accent(instance): accentHex,
        ])
    }
}
