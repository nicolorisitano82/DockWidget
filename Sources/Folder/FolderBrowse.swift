import AppKit

/// One thing in a folder, with the few facts the list needs to sort and show it.
struct FolderEntry {
    var url: URL
    var name: String
    var isDirectory: Bool
    var modified: Date
    var added: Date
    var size: Int64
    var kind: String

    /// The line on the right, which follows whatever the list is sorted by.
    func detail(for sort: FolderSort) -> String {
        switch sort {
        case .name, .kind:
            return isDirectory ? T("cartella", "folder") : kind
        case .size:
            return isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: size,
                                                                 countStyle: .file)
        case .dateAdded:
            return FolderEntry.stamp.string(from: added)
        case .dateModified:
            return FolderEntry.stamp.string(from: modified)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

/// What came back when the folder was read.
enum FolderReading {
    case loading
    case items([FolderEntry])
    /// macOS keeps Desktop, Documents and Downloads behind a permission, and a
    /// refusal looks exactly like an empty folder unless it is said out loud.
    case denied
    case missing
    case failed(String)
}

enum FolderReader {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        .fileSizeKey, .localizedTypeDescriptionKey, .localizedNameKey,
    ]

    static func read(_ folder: URL, showsHidden: Bool) -> FolderReading {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return .missing }
        do {
            let urls = try manager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys,
                options: showsHidden ? [] : [.skipsHiddenFiles])
            return .items(urls.map(entry(for:)))
        } catch let error as NSError {
            switch error.code {
            case NSFileReadNoPermissionError, NSFileReadUnknownError:
                return .denied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .missing
            default:
                return .failed(error.localizedDescription)
            }
        }
    }

    private static func entry(for url: URL) -> FolderEntry {
        let values = try? url.resourceValues(forKeys: Set(keys))
        return FolderEntry(
            url: url,
            name: values?.localizedName ?? url.lastPathComponent,
            isDirectory: values?.isDirectory ?? false,
            modified: values?.contentModificationDate ?? .distantPast,
            added: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast,
            size: Int64(values?.fileSize ?? 0),
            kind: values?.localizedTypeDescription ?? "")
    }

    static func sorted(_ entries: [FolderEntry], by sort: FolderSort,
                       reversed: Bool) -> [FolderEntry] {
        let ordered = entries.sorted { left, right in
            switch sort {
            case .name:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .kind:
                return left.kind == right.kind
                    ? left.name.localizedStandardCompare(right.name) == .orderedAscending
                    : left.kind.localizedStandardCompare(right.kind) == .orderedAscending
            case .size: return left.size > right.size
            case .dateAdded: return left.added > right.added
            case .dateModified: return left.modified > right.modified
            }
        }
        return reversed ? ordered.reversed() : ordered
    }

    /// Copies into a folder without ever overwriting: a name already taken
    /// gets a number, the way the Finder does it.
    @discardableResult
    static func copy(_ urls: [URL], into folder: URL) -> Int {
        let manager = FileManager.default
        var done = 0
        for url in urls {
            var target = folder.appendingPathComponent(url.lastPathComponent)
            let base = url.deletingPathExtension().lastPathComponent
            let suffix = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            var attempt = 2
            while manager.fileExists(atPath: target.path), attempt < 100 {
                target = folder.appendingPathComponent("\(base) \(attempt)\(suffix)")
                attempt += 1
            }
            do {
                try manager.copyItem(at: url, to: target)
                done += 1
            } catch {
                Diagnostics.write("copia non riuscita: \(url.lastPathComponent) — "
                    + error.localizedDescription)
            }
        }
        return done
    }

    /// Asks for the folder out loud, which is the one way a refusal can be
    /// turned into a yes: what the user picks in an open panel is theirs to
    /// give, and the choice is kept so the next launch does not ask again.
    static func requestAccess(to folder: URL, completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = T("Concedi a Underdock l'accesso a questa cartella.",
                          "Let Underdock read this folder.")
        panel.prompt = T("Consenti", "Allow")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let chosen = panel.url else {
            completion(false)
            return
        }
        remember(chosen)
        completion(true)
    }

    private static let bookmarksKey = "folder.grants"

    static func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: [.withSecurityScope],
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil) else { return }
        var kept = SettingsStore.shared.strings(bookmarksKey) ?? []
        let encoded = data.base64EncodedString()
        kept.removeAll { $0 == encoded }
        kept.insert(encoded, at: 0)
        SettingsStore.shared.set(Array(kept.prefix(24)), for: bookmarksKey)
    }

    /// Re-opens what was granted before. Called once, at startup.
    static func restoreGrants() {
        for encoded in SettingsStore.shared.strings(bookmarksKey) ?? [] {
            guard let data = Data(base64Encoded: encoded) else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  !stale else { continue }
            _ = url.startAccessingSecurityScopedResource()
        }
    }
}
