import Foundation

/// Where the processes leave things for each other: published state, relayed
/// artwork, the diagnostics log.
enum SharedPaths {
    static var cache: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/dev.nicolo.underdock", isDirectory: true)
    }
}

/// The plug-in lives inside a process we do not own and whose unified-log
/// output does not survive, so diagnostics go to a file we can read back.
enum Diagnostics {
    static let logURL = SharedPaths.cache.appendingPathComponent("diagnostics.log")

    private static var fired: Set<String> = []
    private static let lock = NSLock()

    /// Writes `message` the first time this `key` is seen in this process.
    static func once(_ key: String, _ message: @autoclosure () -> String) {
        lock.lock()
        let isNew = fired.insert(key).inserted
        lock.unlock()
        guard isNew else { return }
        write(message())
    }

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(ProcessInfo.processInfo.processName)] \(message)\n"
        NSLog("[underdock] %@", message)

        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }

        // Three processes write here — the plug-in inside the Dock, the manager
        // and the agent. Seeking to the end and writing is two steps and they
        // clobber each other; O_APPEND makes a small write atomic.
        let descriptor = open(logURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        data.withUnsafeBytes { buffer in
            _ = Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
    }
}
