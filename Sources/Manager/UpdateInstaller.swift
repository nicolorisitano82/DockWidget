import AppKit
import Security

/// Puts a downloaded disk image in place of the application that is running.
///
/// The image stays the way updates are handed out — it is the same file that
/// gets dragged across by hand, and it is left in Downloads afterwards. What
/// this adds is the dragging: mount it, make sure what is inside is this same
/// application signed by the same hand, stage a copy, and leave the swap to a
/// script that waits for this process to be gone. An application cannot
/// replace its own bundle while it is reading from it.
enum UpdateInstaller {
    /// Where the copy waits between the image and the swap. Under Caches
    /// because it is on the same volume as /Applications, and a move within a
    /// volume is instant — a copy across one is not, and the Dock would be
    /// looking at half a bundle while it ran.
    private static var stagingFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("dev.nicolo.underdock/Update", isDirectory: true)
    }

    /// The bundle to replace: wherever this one is running from, not
    /// /Applications by name. Somebody who keeps it elsewhere gets it updated
    /// there rather than gaining a second copy.
    static var installedApp: URL { Bundle.main.bundleURL }

    /// Whether the swap can be done without asking for a password. Installing
    /// somewhere only an administrator can write is a job for the Finder.
    static var canInstall: Bool {
        let manager = FileManager.default
        let parent = installedApp.deletingLastPathComponent()
        return manager.isWritableFile(atPath: parent.path)
            && manager.isWritableFile(atPath: installedApp.path)
    }

    /// Mounts, checks, stages, and — if all of that held — hands over to the
    /// script and quits. The completion only ever runs when something went
    /// wrong: when it works, the application is not there to hear it.
    static func install(diskImage: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var mounted: URL?
            defer { mounted.map(detach) }
            do {
                let mount = try attach(diskImage)
                mounted = mount
                let fresh = mount.appendingPathComponent("Underdock.app")
                guard FileManager.default.fileExists(atPath: fresh.path) else {
                    throw problem(T("L'immagine non contiene Underdock.",
                                    "The image has no Underdock in it."))
                }
                try check(fresh)
                let staged = try stage(fresh)
                try handOver(staged)
            } catch {
                let message = (error as NSError).localizedDescription
                DispatchQueue.main.async { completion(message) }
            }
        }
    }

    // MARK: The image

    private static func attach(_ diskImage: URL) throws -> URL {
        // -nobrowse so it does not appear in the Finder's sidebar for the few
        // seconds it is there, -mountrandom so it never collides with the same
        // image already mounted by hand.
        let output = try run("/usr/bin/hdiutil",
                             ["attach", diskImage.path, "-nobrowse", "-readonly",
                              "-noautoopen", "-mountrandom", NSTemporaryDirectory(),
                              "-plist"])
        guard let plist = try? PropertyListSerialization.propertyList(
                from: Data(output.utf8), options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let point = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw problem(T("Non sono riuscito ad aprire l'immagine.",
                            "Could not open the image."))
        }
        return URL(fileURLWithPath: point)
    }

    private static func detach(_ mount: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
    }

    // MARK: What is inside it

    /// The new application has to be the same application, signed by whoever
    /// signed this one, and newer. The download already had to come from
    /// GitHub over HTTPS; this is the half that a redirected download, or a
    /// release put out by somebody else, does not get past.
    private static func check(_ fresh: URL) throws {
        var running: SecStaticCode?
        var candidate: SecStaticCode?
        guard SecStaticCodeCreateWithPath(installedApp as CFURL, [], &running) == errSecSuccess,
              let running,
              SecStaticCodeCreateWithPath(fresh as CFURL, [], &candidate) == errSecSuccess,
              let candidate
        else {
            throw problem(T("Non sono riuscito a leggere la firma.",
                            "Could not read the signature."))
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(running, [], &requirement) == errSecSuccess,
              let requirement
        else {
            throw problem(T("Questa copia non è firmata.", "This copy is not signed."))
        }

        let valid = SecStaticCodeCheckValidity(candidate, [], requirement)
        guard valid == errSecSuccess else {
            throw problem(T("La firma dell'aggiornamento non corrisponde.",
                            "The update is signed by somebody else."))
        }

        let plist = fresh.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let version = info["CFBundleShortVersionString"] as? String
        else {
            throw problem(T("L'aggiornamento non dice che versione è.",
                            "The update does not say which version it is."))
        }
        guard Updates.compare(version, Updates.runningVersion) == .orderedDescending else {
            throw problem(T("L'immagine contiene la versione \(version).",
                            "The image holds version \(version)."))
        }
    }

    // MARK: Staging and the swap

    private static func stage(_ fresh: URL) throws -> URL {
        let manager = FileManager.default
        let folder = stagingFolder
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent("Underdock.app")
        // ditto rather than a copy of our own: it is the one that carries a
        // bundle across whole, down to the flags the signature is checked on.
        _ = try run("/usr/bin/ditto", [fresh.path, staged.path])
        return staged
    }

    private static func handOver(_ staged: URL) throws {
        let script = stagingFolder.appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                             staged.path, installedApp.path, stagingFolder.path]
        try process.run()

        DispatchQueue.main.async {
            // Not terminate(_:), which asks the windows first and can be told
            // no: by here the copy is staged and the script is already waiting
            // for this process to go.
            NSApp.terminate(nil)
        }
    }

    private static let swapScript = """
    #!/bin/bash
    # Waits for Underdock to quit, puts the staged copy in its place, and
    # starts it again. Run detached: the application that spawned it is the
    # one it is waiting for.
    set -u
    PID="$1"; STAGE="$2"; TARGET="$3"; SCRATCH="$4"

    for _ in $(seq 1 150); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.2
    done

    # The overlay agent and the widgets are separate processes living inside
    # the bundle that is about to move.
    pkill -f "NowPlayingBar.app/Contents/MacOS/NowPlayingBar" 2>/dev/null || true
    pkill -f "$TARGET/Contents/Library/Widgets/" 2>/dev/null || true

    # Swapped rather than removed and recopied: the Dock watches the files
    # behind its tiles, and a bundle that disappears even for a moment gets its
    # tiles dropped at the next save.
    rm -rf "$TARGET.old"
    if ! mv "$TARGET" "$TARGET.old"; then
      open "$TARGET" 2>/dev/null
      exit 1
    fi
    if ! mv "$STAGE" "$TARGET"; then
      # Same volume or not, the old one goes back before anything else.
      mv "$TARGET.old" "$TARGET"
      open "$TARGET" 2>/dev/null
      exit 1
    fi
    rm -rf "$TARGET.old"
    touch "$TARGET"

    # LaunchServices caches an application's description. Without this, a
    # widget that gained a tile plug-in keeps being read from the old one and
    # the Dock never asks for the plug-in.
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$TARGET" 2>/dev/null

    # And the Dock is still holding the plug-ins of the version that just left.
    killall -KILL Dock 2>/dev/null
    open "$TARGET"

    # The staging folder, by the name it was given rather than by walking up
    # from a path: this is an rm -rf, and the one thing it must not be able to
    # do is take something else with it.
    case "$SCRATCH" in
      */dev.nicolo.underdock/Update) rm -rf "$SCRATCH" ;;
    esac
    """

    // MARK: Odds and ends

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw problem(T("\((tool as NSString).lastPathComponent) è uscito con \(process.terminationStatus).",
                            "\((tool as NSString).lastPathComponent) exited \(process.terminationStatus)."))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func problem(_ message: String) -> NSError {
        NSError(domain: "dev.nicolo.underdock.update", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
