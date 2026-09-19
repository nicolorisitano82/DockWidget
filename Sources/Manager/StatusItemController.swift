import AppKit

/// The manager's only visible trace when its window is closed: a menu-bar item.
///
/// It never shows in the Dock — the Dock is where the widgets live, and an app
/// icon sitting next to them would be one tile of confusion.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onOpen: (WidgetDescriptor?) -> Void

    init(onOpen: @escaping (WidgetDescriptor?) -> Void) {
        self.onOpen = onOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.icon()
            button.image?.isTemplate = true
            button.toolTip = "Dock Widgets"
        }
        statusItem.menu = buildMenu()
    }

    private static func icon() -> NSImage? {
        for name in ["dock.rectangle", "menubar.dock.rectangle", "rectangle.grid.3x1.fill"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Dock Widgets") {
                return image
            }
        }
        return nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuRefresher.shared
        MenuRefresher.shared.controller = self

        let open = NSMenuItem(title: "Apri Dock Widgets", action: #selector(openManager), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        for (index, widget) in WidgetCatalog.all.enumerated() {
            let item = NSMenuItem(title: widget.name, action: #selector(toggleWidget(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = widget.isInstalled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Esci", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// The checkmarks must be right at the moment the menu opens, not at the
    /// moment it was built.
    func refresh(_ menu: NSMenu) {
        for item in menu.items where item.tag < WidgetCatalog.all.count && item.action == #selector(toggleWidget(_:)) {
            item.state = WidgetCatalog.all[item.tag].isInstalled ? .on : .off
        }
    }

    @objc private func openManager() {
        onOpen(nil)
    }

    @objc private func toggleWidget(_ sender: NSMenuItem) {
        let widget = WidgetCatalog.all[sender.tag]
        if widget.isInstalled {
            WidgetInstaller.uninstall(widget)
        } else {
            WidgetInstaller.install(widget)
        }
        sender.state = widget.isInstalled ? .on : .off
    }

    @objc private func quit() {
        // Quitting takes away this menu, nothing else: the tiles are drawn by
        // the Dock's own plug-in host and the bar by its own agent.
        NSApp.terminate(nil)
    }

    /// NSMenu's delegate is weakly held and must outlive the menu.
    private final class MenuRefresher: NSObject, NSMenuDelegate {
        static let shared = MenuRefresher()
        weak var controller: StatusItemController?

        func menuWillOpen(_ menu: NSMenu) {
            controller?.refresh(menu)
        }
    }
}
