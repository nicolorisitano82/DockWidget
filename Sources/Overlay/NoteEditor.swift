import AppKit

/// The note's editor: a small panel that rises above the bar when you click it.
///
/// Unlike the bars, this one takes the keyboard, so it becomes key — and the
/// agent, which normally has no windows at all, activates itself for as long as
/// the panel is open.
final class NoteEditorPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var textView: NSTextView?

    func toggle(above frame: NSRect) {
        if panel != nil {
            close()
        } else {
            show(above: frame)
        }
    }

    private func show(above frame: NSRect) {
        let size = NSSize(width: max(frame.width * 1.6, 320), height: 180)
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY + 14)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scroll.bounds)
        textView.string = NoteSettings.current.text
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        panel.contentView?.addSubview(scroll)
        panel.makeFirstResponder(textView)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.textView = textView
    }

    private func save() {
        guard let textView else { return }
        var settings = NoteSettings.current
        guard settings.text != textView.string else { return }
        settings.text = textView.string
        settings.save()
    }

    func close() {
        save()
        panel?.orderOut(nil)
        panel = nil
        textView = nil
    }

    // Closing, or clicking anywhere else, keeps what was typed.
    func windowWillClose(_ notification: Notification) {
        save()
        panel = nil
        textView = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
