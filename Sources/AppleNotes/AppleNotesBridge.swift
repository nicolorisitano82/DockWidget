import AppKit

struct AppleNote: Codable, Equatable {
    var id: String
    var title: String
    var folder: String
    var modified: Date
    var snippet: String
}

/// Everything about Apple Notes goes through AppleScript: there is no other way
/// in, short of reading the private database behind Full Disk Access.
///
/// Sending those events needs the Automation permission, and it belongs to the
/// process that sends them. So whoever manages to read publishes what it read,
/// and everything else — the Dock plug-in above all — displays that. It is the
/// same arrangement the now-playing widget uses for MediaRemote.
enum AppleNotesBridge {
    static let changed = Notification.Name("dev.nicolo.underdock.notesChanged")

    static var fileURL: URL {
        SharedPaths.cache.appendingPathComponent("applenotes.json")
    }

    struct Snapshot: Codable {
        var folders: [String] = []
        var notes: [AppleNote] = []
        var fetchedAt = Date()
        var failure: String?
    }

    // MARK: Reading what was published

    static func read() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(folders: [], notes: [], fetchedAt: .distantPast, failure: nil)
        }
        return snapshot
    }

    static func observe(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: changed, object: nil, queue: .main
        ) { _ in handler() }
    }

    // MARK: Fetching

    /// Asks Notes for its folders and its most recent notes, off the main
    /// thread: a library with hundreds of notes takes a moment to answer.
    static func refresh(folder: String, limit: Int = 12, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            var snapshot = Snapshot()
            snapshot.folders = run(script: "tell application \"Notes\" to get name of folders")?
                .components(separatedBy: ", ").filter { !$0.isEmpty } ?? []

            let source = folder.isEmpty
                ? "set theNotes to notes"
                : "set theNotes to notes of folder \"\(escape(folder))\""
            let listing = """
            tell application "Notes"
                \(source)
                set output to ""
                repeat with aNote in theNotes
                    set output to output & (id of aNote) & "\t" & (name of aNote) & "\t" ¬
                        & ((modification date of aNote) as «class isot» as string) & linefeed
                end repeat
                return output
            end tell
            """

            if let result = run(script: listing) {
                snapshot.notes = parse(result, folder: folder)
                    .sorted { $0.modified > $1.modified }
                    .prefix(limit)
                    .map { $0 }
                snapshot.notes = withSnippets(snapshot.notes)
            } else {
                snapshot.failure = T("Note non ha risposto. Serve il permesso di automazione.",
                                     "Notes did not answer. Automation permission is needed.")
            }

            publish(snapshot)
            DispatchQueue.main.async { completion?() }
        }
    }

    /// The body of the newest note only: asking for every body turns a quick
    /// query into a slow one.
    private static func withSnippets(_ notes: [AppleNote]) -> [AppleNote] {
        guard var first = notes.first else { return notes }
        let script = """
        tell application "Notes" to get plaintext of note id "\(escape(first.id))"
        """
        if let body = run(script: script) {
            let text = body
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .dropFirst()            // the first line is the title again
                .joined(separator: " ")
            first.snippet = String(text.prefix(200))
        }
        var updated = notes
        updated[0] = first
        return updated
    }

    private static func parse(_ text: String, folder: String) -> [AppleNote] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return text.components(separatedBy: .newlines).compactMap { line in
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3, !fields[1].isEmpty else { return nil }
            return AppleNote(id: fields[0], title: fields[1], folder: folder,
                             modified: formatter.date(from: fields[2]) ?? .distantPast,
                             snippet: "")
        }
    }

    private static func publish(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(at: SharedPaths.cache,
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    // MARK: Acting

    static func open(_ note: AppleNote) {
        _ = run(script: """
        tell application "Notes"
            activate
            show note id "\(escape(note.id))"
        end tell
        """)
    }

    static func openApp() {
        _ = run(script: "tell application \"Notes\" to activate")
    }

    static func createNote(in folder: String) {
        let target = folder.isEmpty ? "" : " at folder \"\(escape(folder))\""
        _ = run(script: """
        tell application "Notes"
            activate
            set fresh to make new note\(target) with properties {body:"<div><br></div>"}
            show fresh
        end tell
        """)
    }

    // MARK: Plumbing

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private static func run(script source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Diagnostics.once("notes-\(error["NSAppleScriptErrorNumber"] ?? "?")",
                             "Note: \(error["NSAppleScriptErrorMessage"] ?? error)")
            return nil
        }
        return result?.stringValue
    }
}
