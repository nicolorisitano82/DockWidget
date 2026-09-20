import AppKit

/// What a widget does with files dropped on its Dock tile.
///
/// Drag and drop reaches the helper app, not the plug-in — the Dock delivers
/// dropped files to the application that owns the tile — so the handling lives
/// here, where the helper can reach it without linking a widget's whole code.
enum WidgetDrop {
    /// Returns true when the files were dealt with, so the helper knows not to
    /// treat the launch as a plain click.
    @discardableResult
    static func handle(widgetID: String, files: [URL]) -> Bool {
        switch widgetID {
        case "folder":
            // The key is spelled out rather than imported: the helper links
            // only the shared code, and this is the one thing it needs from
            // the folder widget.
            let path = SettingsStore.shared.string("folder.path", or: "")
            guard !path.isEmpty else { return false }
            let destination = URL(fileURLWithPath: path)
            for file in files {
                var target = destination.appendingPathComponent(file.lastPathComponent)
                var attempt = 2
                while FileManager.default.fileExists(atPath: target.path), attempt < 100 {
                    // Never overwrite something already in the folder.
                    let name = file.deletingPathExtension().lastPathComponent
                    let suffix = file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)"
                    target = destination.appendingPathComponent("\(name) \(attempt)\(suffix)")
                    attempt += 1
                }
                try? FileManager.default.moveItem(at: file, to: target)
            }
            return true
        default:
            return false
        }
    }
}
