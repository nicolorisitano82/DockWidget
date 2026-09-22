import AppKit

/// Asks whether there is a newer Underdock, and fetches it when told to.
///
/// Nothing happens on the quiet: the disk image lands in Downloads like any
/// other download, and what happens next is asked. Putting it in place is
/// offered — the image is the same one that gets dragged across by hand, and
/// it stays in Downloads either way.
final class UpdateController: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateController()

    private var busy = false
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var pending: Release?
    private var progressPanel: NSPanel?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?

    private override init() { super.init() }

    /// Asked for out loud: says so even when there is nothing new, and shows
    /// what went wrong when something does.
    @objc func checkForUpdates(_ sender: Any?) { check(loud: true) }

    /// At launch: only if the preference allows it, only once a day, and silent
    /// unless there is something to say.
    func checkQuietlyIfDue() {
        guard SettingsStore.shared.bool(Updates.Key.automatic, or: true) else { return }
        let last = SettingsStore.shared.double(Updates.Key.lastCheck, or: 0)
        let date = last > 0 ? Date(timeIntervalSince1970: last) : nil
        guard Updates.isDue(lastCheck: date) else { return }
        check(loud: false)
    }

    private func check(loud: Bool) {
        guard !busy else { return }
        busy = true
        Updates.latest { [weak self] release, problem in
            guard let self else { return }
            self.busy = false
            SettingsStore.shared.set(Date().timeIntervalSince1970, for: Updates.Key.lastCheck)

            guard let release else {
                guard loud else { return }
                self.say(T("Non sono riuscito a chiedere a GitHub.",
                           "Could not ask GitHub."), detail: problem ?? "")
                return
            }
            guard Updates.isNewer(release, than: Updates.runningVersion) else {
                guard loud else { return }
                self.say(T("Underdock è aggiornato.", "Underdock is up to date."),
                         detail: T("Hai la versione \(Updates.runningVersion).",
                                   "You have version \(Updates.runningVersion)."))
                return
            }
            self.offer(release)
        }
    }

    // MARK: Asking

    private func say(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = T("C'è Underdock \(release.version).",
                              "Underdock \(release.version) is out.")

        var notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 400 {
            notes = String(notes.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        var detail = T("Hai la \(Updates.runningVersion).", "You have \(Updates.runningVersion).")
        if release.size > 0 {
            detail += " " + ByteCountFormatter.string(fromByteCount: release.size, countStyle: .file)
        }
        if !notes.isEmpty { detail += "\n\n" + notes }
        alert.informativeText = detail

        alert.addButton(withTitle: T("Scarica", "Download"))
        alert.addButton(withTitle: T("Non ora", "Not now"))
        if release.pageURL != nil {
            alert.addButton(withTitle: T("Note di rilascio", "Release notes"))
        }

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            fetch(release)
        case .alertThirdButtonReturn:
            release.pageURL.map { NSWorkspace.shared.open($0) }
        default:
            break
        }
    }

    // MARK: Fetching

    private func fetch(_ release: Release) {
        guard let url = release.diskImageURL else {
            say(T("Questa versione non ha un'immagine disco.",
                  "That release has no disk image."),
                detail: T("Scaricala dalla pagina del rilascio.",
                          "Download it from the release page."))
            release.pageURL.map { NSWorkspace.shared.open($0) }
            return
        }
        guard Updates.isTrusted(url) else {
            // A feed that has been tampered with should not be able to send
            // this off to fetch something from somewhere else.
            say(T("Il file non viene da GitHub.", "That file does not come from GitHub."),
                detail: url.absoluteString)
            return
        }

        pending = release
        busy = true
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self,
                                 delegateQueue: .main)
        self.session = session
        task = session.downloadTask(with: url)
        showProgress(for: release)
        task?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else {
            progressBar?.isIndeterminate = true
            return
        }
        progressBar?.isIndeterminate = false
        progressBar?.doubleValue = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let done = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let all = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite,
                                            countStyle: .file)
        progressLabel?.stringValue = "\(done) / \(all)"
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let name = pending?.diskImageURL?.lastPathComponent ?? "Underdock.dmg"
        let destination = Updates.freeFile(in: Updates.downloadsFolder(), named: name)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finish()
            say(T("Non sono riuscito a metterlo nei Download.",
                  "Could not put it in Downloads."), detail: error.localizedDescription)
            return
        }
        let version = pending?.version ?? ""
        finish()
        offerToInstall(destination, version: version)
    }

    /// The downloaded image, and the two things that can be done with it.
    ///
    /// Installing is only offered where it can be done without a password:
    /// a copy sitting somewhere only an administrator can write is a job for
    /// the Finder, and saying so up front beats failing halfway.
    private func offerToInstall(_ diskImage: URL, version: String) {
        guard UpdateInstaller.canInstall else {
            NSWorkspace.shared.activateFileViewerSelecting([diskImage])
            return
        }

        let alert = NSAlert()
        alert.messageText = T("Underdock \(version) è nei Download.",
                              "Underdock \(version) is in Downloads.")
        alert.informativeText = T(
            "Posso metterlo al posto di questa copia: Underdock si chiude, si sostituisce e riparte. L'immagine resta nei Download.",
            "I can put it in place of this copy: Underdock quits, is replaced, and starts again. The image stays in Downloads.")
        alert.addButton(withTitle: T("Installa e riavvia", "Install and restart"))
        alert.addButton(withTitle: T("Mostra nel Finder", "Show in Finder"))

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSWorkspace.shared.activateFileViewerSelecting([diskImage])
            return
        }

        UpdateInstaller.install(diskImage: diskImage) { [weak self] problem in
            // Only ever called when it did not happen: when it does, this
            // process is already gone.
            self?.say(T("Non sono riuscito a installarlo.", "Could not install it."),
                      detail: problem)
            NSWorkspace.shared.activateFileViewerSelecting([diskImage])
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish()
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        guard !cancelled else { return }
        say(T("Il download non è riuscito.", "The download failed."),
            detail: error.localizedDescription)
    }

    private func finish() {
        busy = false
        task = nil
        session?.invalidateAndCancel()
        session = nil
        pending = nil
        hideProgress()
    }

    @objc private func stopDownload() {
        task?.cancel()
        finish()
    }

    // MARK: Showing how far along it is

    private func showProgress(for release: Release) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 108),
                            styleMask: [.titled, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = T("Underdock \(release.version)", "Underdock \(release.version)")
        panel.isFloatingPanel = true
        panel.center()

        let heading = NSTextField(labelWithString: T("Sto scaricando…", "Downloading…"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        let bar = NSProgressIndicator()
        bar.isIndeterminate = true
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.startAnimation(nil)
        progressBar = bar

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        progressLabel = label

        let stop = NSButton(title: T("Annulla", "Cancel"), target: self,
                            action: #selector(stopDownload))

        let stack = NSStackView(views: [heading, bar, label, stop])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = stack
        bar.widthAnchor.constraint(equalToConstant: 320).isActive = true

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressPanel = panel
    }

    private func hideProgress() {
        progressPanel?.orderOut(nil)
        progressPanel = nil
        progressBar = nil
        progressLabel = nil
    }
}
