import AppKit

/// The manager's only visible trace when its window is closed: a menu-bar item.
///
/// It never shows in the Dock — the Dock is where the widgets live, and an app
/// icon sitting next to them would be one tile of confusion.
final class StatusItemController {
    private let loginItemTag = 900
    private let backgroundItemTag = 901
    private let statusItem: NSStatusItem
    private let onOpen: (String?) -> Void

    init(onOpen: @escaping (String?) -> Void) {
        self.onOpen = onOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.icon()
            button.image?.isTemplate = true
            button.toolTip = "Underdock"
        }
        statusItem.menu = buildMenu()
    }

    private static func icon() -> NSImage? {
        for name in ["dock.rectangle", "menubar.dock.rectangle", "rectangle.grid.3x1.fill"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Underdock") {
                return image
            }
        }
        return nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuRefresher.shared
        MenuRefresher.shared.controller = self

        let open = NSMenuItem(title: T("Apri Underdock", "Open Underdock"), action: #selector(openManager), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let background = NSMenuItem(title: T("Sfondo dietro i widget", "Panel behind the widgets"),
                                    action: #selector(toggleBackground(_:)), keyEquivalent: "")
        background.target = self
        background.tag = backgroundItemTag
        background.state = WidgetChrome.showsBackground ? .on : .off
        menu.addItem(background)

        let login = NSMenuItem(title: T("Apri al login", "Open at login"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.tag = loginItemTag
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: T("Esci e libera il Dock", "Quit and free the Dock"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// The checkmarks must be right at the moment the menu opens, not at the
    /// moment it was built.
    func refresh(_ menu: NSMenu) {
        for item in menu.items {
            if item.tag == backgroundItemTag {
                item.state = WidgetChrome.showsBackground ? .on : .off
            }
            if item.tag == loginItemTag {
                item.state = LoginItem.isEnabled ? .on : .off
                item.title = LoginItem.needsApproval ? T("Apri al login (da approvare)", "Open at login (needs approval)") : T("Apri al login", "Open at login")
            }
        }
    }

    @objc private func toggleBackground(_ sender: NSMenuItem) {
        WidgetChrome.setShowsBackground(sender.state != .on)
        sender.state = WidgetChrome.showsBackground ? .on : .off
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let error = LoginItem.set(sender.state != .on)
        sender.state = LoginItem.isEnabled ? .on : .off
        guard let error else { return }
        let alert = NSAlert()
        alert.messageText = "Non sono riuscito a impostare l'apertura al login"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func openManager() {
        onOpen(nil)
    }

    @objc private func quit() {
        // The widgets outlive this process — the Dock draws the tiles itself —
        // so leaving them behind would mean a Dock full of widgets nothing is
        // managing. They come back at the next launch.
        WidgetInstaller.uninstallAllForQuit()
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
