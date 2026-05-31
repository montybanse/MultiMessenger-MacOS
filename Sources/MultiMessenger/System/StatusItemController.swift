import AppKit
import SwiftUI

/// Symbol in der macOS-Menüleiste mit Gesamtzahl ungelesener Nachrichten.
/// Links-Klick öffnet ein Popover mit der Dienst-Übersicht, Rechts-Klick ein Menü.
@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    var onShow: (() -> Void)?
    var onToggleDND: (() -> Void)?
    var onQuit: (() -> Void)?
    /// Liefert den Inhalt des Popovers (SwiftUI), z.B. die Dienst-Übersicht.
    var popoverContent: (() -> AnyView)?

    private(set) var dndEnabled = false

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: "MultiMessenger")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        statusItem = item
    }

    func update(totalUnread: Int, dndEnabled: Bool) {
        self.dndEnabled = dndEnabled
        guard let button = statusItem?.button else { return }
        button.title = totalUnread > 0 ? " \(totalUnread)" : ""
        let symbol = dndEnabled ? "moon.fill" : "bubble.left.and.bubble.right.fill"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MultiMessenger")
    }

    // MARK: Klick-Verteilung

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    func closePopover() { popover.performClose(nil) }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let content = popoverContent?() {
            popover.contentViewController = NSHostingController(rootView: content)
            popover.contentSize = NSSize(width: 320, height: 420)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil   // nur für diesen Klick, sonst blockiert es das Popover
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
