import AppKit

/// Makes and unmakes copies of a widget.
///
/// A copy is the template bundle with another name and another identifier,
/// kept outside the app so that updating the app cannot pull it out from under
/// the Dock. It is signed on the spot: unsigned code does not run, and the
/// Dock's plug-in host will load a signature that is not Apple's but refuses
/// one that is broken.
enum InstanceFactory {
    static func create(from template: WidgetDescriptor) -> WidgetDescriptor? {
        let instance = WidgetInstances.add(to: template.kind)
        let copy = WidgetInstance.copy(of: instance)
        let descriptor = template.copy(number: copy)

        do {
            try materialise(descriptor, from: template)
            return descriptor
        } catch {
            WidgetInstances.remove(instance)
            let alert = NSAlert()
            alert.messageText = T("Non sono riuscito a creare la copia",
                                  "Could not create the copy")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }

    static func destroy(_ widget: WidgetDescriptor) {
        guard widget.copy > 1 else { return }
        WidgetInstaller.uninstall(widget)
        try? FileManager.default.removeItem(at: widget.helperURL)
        WidgetInstances.remove(widget.id)
        SettingsStore.shared.removeAll(withPrefix: widget.id + ".")
    }

    /// Brings every copy back in step with the app after an update.
    ///
    /// The bundles live outside the app, so a new version of a widget does not
    /// reach them on its own — and a copy running last month's code beside this
    /// month's original is the kind of difference nobody would think to look for.
    static func refreshAll() {
        for kind in WidgetCatalog.kinds {
            for instance in WidgetInstances.all(of: kind.kind) where instance != kind.kind {
                let descriptor = kind.copy(number: WidgetInstance.copy(of: instance))
                guard isStale(descriptor, against: kind) else { continue }
                try? materialise(descriptor, from: kind)
            }
        }
    }

    private static func isStale(_ descriptor: WidgetDescriptor,
                                against template: WidgetDescriptor) -> Bool {
        guard descriptor.exists else { return true }
        let attributes = { (url: URL) -> Date in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
                .flatMap { $0 } ?? .distantPast
        }
        return attributes(descriptor.helperURL) < attributes(template.helperURL)
    }

    private static func materialise(_ descriptor: WidgetDescriptor,
                                    from template: WidgetDescriptor) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: WidgetInstance.copiesDirectory,
                                    withIntermediateDirectories: true)

        let destination = descriptor.helperURL
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: template.helperURL, to: destination)

        plist(destination.appendingPathComponent("Contents/Info.plist"), [
            "CFBundleIdentifier": descriptor.bundleID,
            "CFBundleName": descriptor.name,
            "CFBundleDisplayName": descriptor.name,
        ])
        if let plugin = pluginBundle(in: destination) {
            plist(plugin.appendingPathComponent("Contents/Info.plist"), [
                "CFBundleIdentifier": descriptor.bundleID + ".tile",
            ])
            sign(plugin)
        }
        sign(destination)
    }

    private static func pluginBundle(in app: URL) -> URL? {
        let plugins = app.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(at: plugins,
                                                             includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "docktileplugin" }
    }

    private static func plist(_ url: URL, _ values: [String: String]) {
        guard let data = try? Data(contentsOf: url),
              var contents = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return }
        for (key, value) in values { contents[key] = value }
        guard let written = try? PropertyListSerialization.data(fromPropertyList: contents,
                                                                format: .xml, options: 0) else { return }
        try? written.write(to: url)
    }

    /// The local identity when there is one, ad-hoc otherwise: both are loaded
    /// by the Dock, and neither travels to another Mac.
    private static func sign(_ url: URL) {
        let identity = localIdentity ?? "-"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--force", "--sign", identity, "--timestamp=none", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// The certificate was called "Dock Widgets Dev" before the app was
    /// renamed, and an installed Mac still has that one in its keychain. Both
    /// names are accepted so a rename does not quietly drop every copy back to
    /// an ad-hoc signature.
    static let identityNames = ["Underdock Dev", "WidgetPro Dev", "Dock Widgets Dev"]

    private static let localIdentity: String? = {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-identity", "-v", "-p", "codesigning"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let listing = String(data: data, encoding: .utf8) ?? ""
        return identityNames.first { listing.contains($0) }
    }()
}
