import AppKit

/// Holds the Dock still while the preview is open in front of it.
///
/// Its own preferences are no use: a running Dock never re-reads them — writing
/// `magnification`, or even `tilesize`, changes nothing until it restarts. What
/// does work is CoreDock, the private interface System Settings itself goes
/// through, which changes the live state.
///
/// The functions are looked up by name at run time rather than linked, so a
/// system that no longer has them costs the freeze and nothing else.
enum DockFreeze {
    private typealias GetFlag = @convention(c) () -> Bool
    private typealias SetFlag = @convention(c) (Bool) -> Void

    /// Remembered in the settings rather than in memory: if the agent goes away
    /// with the preview open, the next one to start puts the Dock back.
    private static let key = "dock.magnificationHeld"

    private struct Entry {
        var isMagnified: GetFlag
        var setMagnified: SetFlag
    }

    private static let entry: Entry? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework"
            + "/Frameworks/HIServices.framework/HIServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "CoreDockIsMagnificationEnabled"),
              let set = dlsym(handle, "CoreDockSetMagnificationEnabled") else {
            Diagnostics.once("dockfreeze", "CoreDock non disponibile: il Dock resterà vivo")
            return nil
        }
        return Entry(isMagnified: unsafeBitCast(get, to: GetFlag.self),
                     setMagnified: unsafeBitCast(set, to: SetFlag.self))
    }()

    /// Called at startup, in case a previous run went away mid-preview.
    static func restoreIfNeeded() {
        guard SettingsStore.shared.bool(key, or: false) else { return }
        entry?.setMagnified(true)
        SettingsStore.shared.set(false, for: key)
        Diagnostics.write("ingrandimento del Dock rimesso dopo una chiusura brusca")
    }

    static func hold() {
        guard let entry, entry.isMagnified() else { return }
        entry.setMagnified(false)
        SettingsStore.shared.set(true, for: key)
    }

    static func release() {
        guard SettingsStore.shared.bool(key, or: false) else { return }
        entry?.setMagnified(true)
        SettingsStore.shared.set(false, for: key)
    }
}
