import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()
    lazy var manager = WebViewManager(appState: app)
    let icons = IconCache()

    private let statusItem = StatusItemController()
    private var cancellables = Set<AnyCancellable>()
    private var didConfigureWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Web-Daten der alten Bundle-ID übernehmen (einmalig, vor jeder WebView).
        Self.migrateLegacyWebKitData()

        // Werbe-/Tracker-Regeln vorkompilieren (greifen für neue WebViews).
        AdBlocker.prepare()

        // Mitteilungen
        NotificationManager.shared.setup()
        NotificationManager.shared.onActivateService = { [weak self] id in
            self?.app.select(id)
            self?.showMainWindow()
        }

        // Menüleisten-Symbol
        statusItem.install()
        statusItem.onShow = { [weak self] in self?.showMainWindow() }
        statusItem.onToggleDND = { [weak self] in self?.app.settings.dndEnabled.toggle() }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.popoverContent = { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                MenuBarPanel(
                    onOpenService: { [weak self] id in
                        self?.app.select(id)
                        self?.statusItem.closePopover()
                        self?.showMainWindow()
                    },
                    onOpenMain: { [weak self] in
                        self?.statusItem.closePopover()
                        self?.showMainWindow()
                    }
                )
                .environmentObject(self.app)
                .environmentObject(self.icons)
                .environmentObject(self.manager)
            )
        }

        // Globaler Hotkey
        HotKeyManager.shared.onTrigger = { [weak self] in self?.showMainWindow() }
        if app.settings.globalHotkeyEnabled {
            HotKeyManager.shared.register()
        }

        // Autostart-Status mit Systemzustand abgleichen
        app.settings.startAtLogin = LoginItem.isEnabled

        // Status-Symbol bei Änderungen aktualisieren
        app.$unread
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        app.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        refreshStatusItem()

        // Als Anbieter für das macOS-Dienste-/Teilen-Menü registrieren.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // Fenster für nahtlose Titelleiste + Doppelklick-Zoom konfigurieren.
        DispatchQueue.main.async { [weak self] in self?.configureMainWindow() }

        // „Immer wach“-Dienste im Hintergrund vorladen (Benachrichtigungen ab Start).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.manager.preloadAlwaysAwake()
        }

        // Auf neue Version prüfen (gedrosselt auf 1x pro Tag).
        UpdateChecker.shared.checkAtLaunch(enabled: app.settings.updateCheckEnabled)
    }

    /// Die Bundle-ID wurde mit v0.3.0 gewechselt (eu.montybanse.MultiMessenger →
    /// …MultiMessengerApp), weil sich die alte ID in den Benachrichtigungs-Caches
    /// von macOS dauerhaft als „App ohne Icon" eingebrannt hatte. Die Sessions/
    /// Cookies der Dienste liegen aber unter ~/Library/WebKit/<bundle-id> bzw.
    /// ~/Library/HTTPStorages/<bundle-id> – beim ersten Start mit neuer ID einmal
    /// umziehen, damit niemand neu eingeloggt werden muss.
    private static func migrateLegacyWebKitData() {
        let oldID = "eu.montybanse.MultiMessenger"
        guard let newID = Bundle.main.bundleIdentifier, newID != oldID else { return }
        let fm = FileManager.default
        guard let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for sub in ["WebKit", "HTTPStorages"] {
            let old = lib.appendingPathComponent(sub).appendingPathComponent(oldID)
            let new = lib.appendingPathComponent(sub).appendingPathComponent(newID)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
                NSLog("Migration: \(sub)/\(oldID) → \(newID)")
            }
        }
    }

    // MARK: URL-Schema (Links von außen an einen Dienst übergeben)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { route(url) }
    }

    /// Verarbeitet `mmsg://<echte-URL>`, `mmsg://open?url=<encoded>` sowie
    /// direkt übergebene http/https-Links („Öffnen mit“-Menü).
    /// Sucht den Dienst, dessen Host zur Ziel-URL passt, lädt die URL dort und
    /// holt das Fenster nach vorne. Praktisch für BBB-Links aus dem Kalender.
    private func route(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        var target = ""
        var isShare = false

        switch scheme {
        case "http", "https":
            // Direkt geöffneter Web-Link -> wie geteilte URL behandeln.
            target = url.absoluteString
        case "mmsg":
            // Ziel-URL extrahieren.
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let q = comps.queryItems?.first(where: { $0.name == "url" })?.value, !q.isEmpty {
                target = q
            } else {
                // Alles nach "mmsg://" bzw. "mmsg:" als rohe URL behandeln.
                var s = url.absoluteString
                if let r = s.range(of: "mmsg://") { s.removeSubrange(s.startIndex..<r.upperBound) }
                else if let r = s.range(of: "mmsg:") { s.removeSubrange(s.startIndex..<r.upperBound) }
                target = s.removingPercentEncoding ?? s
            }
            isShare = url.host?.lowercased() == "share"
                || url.absoluteString.lowercased().contains("mmsg://share")
        default:
            return
        }
        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        if !target.contains("://") { target = "https://" + target }

        // „share“ -> immer Auswahldialog. Sonst per Host automatisch zuordnen.
        if isShare {
            app.pendingShareURL = target
            showMainWindow()
            return
        }

        let host = URL(string: target)?.host
        let match = app.services.first { svc in
            guard let h = host,
                  let svcHost = URL(string: svc.urlString.contains("://") ? svc.urlString : "https://" + svc.urlString)?.host
            else { return false }
            return svcHost == host || h.hasSuffix(svcHost) || svcHost.hasSuffix(h)
        }

        if let svc = match {
            app.select(svc.id)
            manager.load(urlString: target, into: svc)
        } else {
            // Kein passender Dienst -> Auswahldialog anbieten.
            app.pendingShareURL = target
        }
        showMainWindow()
    }

    // MARK: macOS-Dienst (Services-/Teilen-Menü)

    /// Vom System aufgerufen, wenn der Nutzer eine URL/Text an MultiMessenger
    /// „teilt“ (NSServices-Eintrag, siehe Info.plist).
    @objc func handleShareService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        var shared: String?
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
            shared = first.absoluteString
        } else if let str = pboard.string(forType: .string) {
            shared = str
        }
        guard let s = shared?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        app.pendingShareURL = s.contains("://") ? s : "https://" + s
        showMainWindow()
    }

    // MARK: Fenster

    private func configureMainWindow() {
        guard !didConfigureWindow, let window = mainWindow else { return }
        didConfigureWindow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        // Doppelklick auf die Titelleiste -> Zoom (Systemverhalten respektieren).
        UserDefaults.standard.register(defaults: ["AppleActionOnDoubleClick": "Maximize"])
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") ?? false } ?? NSApp.windows.first
    }

    private func refreshStatusItem() {
        statusItem.update(totalUnread: app.totalUnread, dndEnabled: app.settings.dndEnabled)
        NSApp.dockTile.badgeLabel = app.totalUnread > 0 ? "\(app.totalUnread)" : nil
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        configureMainWindow()
    }

    // Im Hintergrund weiterlaufen (Benachrichtigungen), wenn gewünscht.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !app.settings.keepRunningInBackground
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }
}
