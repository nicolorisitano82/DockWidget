import AppKit

/// Performs what a cell was configured to do.
enum ActionRunner {
    static func run(_ kind: ActionKind) {
        switch kind {
        case .none:
            break
        case .app(let path):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        case .open(let target):
            open(target)
        case .shortcut(let name):
            shell("/usr/bin/shortcuts", ["run", name])
        case .system(let action):
            perform(action)
        }
    }

    private static func open(_ target: String) {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            let path = (target as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        let text = target.contains("://") ? target : "https://\(target)"
        guard let url = URL(string: text) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func perform(_ action: SystemAction) {
        switch action {
        case .lockScreen:
            lockScreen()
        case .sleep:
            shell("/usr/bin/pmset", ["sleepnow"])
        case .screenSaver:
            shell("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case .missionControl:
            shell("/usr/bin/open", ["-a", T("Mission Control", "Mission Control")])
        case .showDesktop:
            // F11 is the default binding; posting the key is the only way in
            // without a private Dock API.
            tapKey(103)
        case .emptyTrash:
            script("tell application \"Finder\" to empty trash")
        case .playPause:
            // Through the Dock plug-in when it is there, through the media keys
            // when it is not.
            NowPlayingControl.send(.togglePlayPause)
        case .screenshot:
            shell("/usr/sbin/screencapture", ["-i", "-c"])
        }
    }

    /// Locks the screen.
    ///
    /// The old recipe — CGSession inside the user menu extra — points at a
    /// path macOS no longer has, and a missing executable fails quietly, which
    /// is exactly how this looked: a button that did nothing. The login
    /// framework still has the call the menu bar itself uses, and a keystroke
    /// stands behind it.
    private static func lockScreen() {
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
            return
        }
        // Control-Command-Q, the shortcut the system offers for the same thing.
        tapKey(12, flags: [.maskCommand, .maskControl])
    }

    private static func tapKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func script(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                Diagnostics.write("azione AppleScript non riuscita: \(error)")
            }
        }
    }

    private static func shell(_ path: String, _ arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            Diagnostics.write("eseguibile mancante: \(path)")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        do {
            try task.run()
        } catch {
            Diagnostics.write("azione non riuscita (\(path)): \(error.localizedDescription)")
        }
    }
}
