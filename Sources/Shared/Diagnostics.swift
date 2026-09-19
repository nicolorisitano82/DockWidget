import Foundation

/// The plug-in lives inside a process we do not own and whose unified-log
/// output does not survive, so diagnostics go to a file we can read back.
enum Diagnostics {
    static let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/dev.nicolo.dockwidgets", isDirectory: true)
        .appendingPathComponent("diagnostics.log")

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
        NSLog("[dockwidgets] %@", message)

        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
