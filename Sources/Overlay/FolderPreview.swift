import AppKit

/// What a folder tile shows when it is clicked: a pane of glass above the Dock
/// with the folder's contents in it, where you can go into subfolders, sort,
/// and leave for the Finder.
///
/// The Dock does this for the folders it keeps in `persistent-others`, and
/// there is no way to ask it to do the same for an application's tile — which
/// is what a widget is. So it is drawn here, in the agent: the process that is
/// already running, already allowed to ask the Dock where its tiles are, and
/// already in the business of putting panels on the screen.
final class FolderPreviewPanel: NSObject {
    private var panel: NSPanel?
    private var monitor: Any?
    private var instance = "folder"

    /// What is waiting to be copied, when the panel was opened by a drop.
    private var dropping: [URL] = []

    /// Opened by something dropped on the tile: the same panel, asking where
    /// the files should go.
    func drop(instance: String, files: [URL]) {
        close()
        self.instance = instance
        dropping = files
        show()
        dropping = []
    }

    /// Shown for this widget, or put away if it is already showing for it.
    func toggle(instance: String) {
        if panel != nil {
            let wasShowing = self.instance == instance
            close()
            if wasShowing { return }
        }
        self.instance = instance
        show()
    }

    private func show() {
        let settings = FolderSettings.current(instance)
        guard let folder = settings.url else { return }

        let title = WidgetInstance.anchorTitle(base: "Cartella",
                                               copy: WidgetInstance.copy(of: instance))
        guard let tile = DockAccessibility.tileFrame(title: title) else {
            // No tile means no idea where to put the panel, and a panel in the
            // wrong place is worse than the folder simply opening.
            Diagnostics.once("folder-preview-tile",
                             "tile \(title) non trovata: apro la cartella invece dell'anteprima")
            NSWorkspace.shared.open(folder)
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(tile) })
            ?? NSScreen.main else { return }

        // A window over the whole screen, above the Dock, so the glass can be
        // placed anywhere above the tile without being clipped.
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
                                    .ignoresCycle]

        let backdrop = DismissingView(frame: NSRect(origin: .zero, size: screen.frame.size))
        backdrop.onDismiss = { [weak self] in self?.close() }
        panel.contentView = backdrop

        let tileInView = NSRect(x: tile.minX - screen.frame.minX,
                                y: tile.minY - screen.frame.minY,
                                width: tile.width, height: tile.height)

        let sheet = FolderSheet(instance: instance, folder: folder, dropping: dropping)
        sheet.onOpenItem = { [weak self] url in
            NSWorkspace.shared.open(url)
            self?.close()
        }
        sheet.onOpenFolder = { [weak self] url in
            NSWorkspace.shared.open(url)
            self?.close()
        }
        // Going into a folder changes how much there is to show, so the glass
        // is measured again rather than left at the size the first level had.
        sheet.onHeightChange = { [weak sheet] in
            sheet?.remeasure(above: tileInView, within: backdrop.bounds)
        }
        sheet.place(above: tileInView, within: backdrop.bounds,
                    ceiling: screen.visibleFrame.maxY - screen.frame.minY - 8)
        backdrop.addSubview(sheet)
        backdrop.glass = sheet

        panel.orderFrontRegardless()
        // And the Dock stops bulging behind it, the way it does for its own
        // stacks. Its clicks still reach it — Apple's stacks do not block them
        // either — and any click outside the glass puts this away first.
        DockFreeze.hold()
        sheet.appear()

        // The Dock receives its clicks by a route of its own, over the top of
        // any window we can put in front of it, so the panel cannot rely on
        // catching them itself: it watches for a click anywhere instead.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let point = NSPoint(x: NSEvent.mouseLocation.x - panel.frame.minX,
                                y: NSEvent.mouseLocation.y - panel.frame.minY)
            if !sheet.frame.contains(point) { self.close() }
        }

        self.panel = panel
    }

    func close() {
        guard panel != nil else { return }
        DockFreeze.release()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The whole screen, minus the glass: a click here means "enough".
final class DismissingView: NSView {
    var onDismiss: (() -> Void)?
    weak var glass: NSView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard glass?.frame.contains(point) != true else { return }
        onDismiss?()
    }

    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
}

