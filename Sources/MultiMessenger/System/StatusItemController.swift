import AppKit

/// Symbol in der macOS-Menüleiste mit Gesamtzahl ungelesener Nachrichten.
@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    var onShow: (() -> Void)?
    var onToggleDND: (() -> Void)?
    var onQuit: (() -> Void)?
    private(set) var dndEnabled = false

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: "MultiMessenger")
            button.imagePosition = .imageLeading
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func update(totalUnread: Int, dndEnabled: Bool) {
        self.dndEnabled = dndEnabled
        guard let button = statusItem?.button else { return }
        button.title = totalUnread > 0 ? " \(totalUnread)" : ""
        let symbol = dndEnabled ? "moon.fill" : "bubble.left.and.bubble.right.fill"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MultiMessenger")
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let show = NSMenuItem(title: "MultiMessenger öffnen", action: #selector(showAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let dnd = NSMenuItem(title: "Nicht stören", action: #selector(dndAction), keyEquivalent: "")
        dnd.target = self
        dnd.state = dndEnabled ? .on : .off
        menu.addItem(dnd)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Beenden", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func showAction() { onShow?() }
    @objc private func dndAction() { onToggleDND?() }
    @objc private func quitAction() { onQuit?() }
}
