import AppKit
import WebKit
import Combine

/// Verwaltet den Pool lebender WKWebViews. Inaktive Dienste werden – je nach
/// Einstellung – nach einer Wartezeit entladen, um RAM zu sparen.
@MainActor
final class WebViewManager: ObservableObject {
    private var pool: [UUID: ServiceWebView] = [:]
    private var sleepTimers: [UUID: Timer] = [:]

    /// IDs der aktuell geladenen (wachen) Dienste. Wird gespiegelt aus `pool`,
    /// damit die Oberfläche das Pause-Symbol anzeigen kann. Aktualisierung erfolgt
    /// asynchron, um keine Mutation während eines View-Updates auszulösen.
    @Published private(set) var awakeIDs: Set<UUID> = []

    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Liefert (und erzeugt bei Bedarf) die WebView für einen Dienst.
    func webView(for service: Service) -> WKWebView {
        cancelSleep(service.id)
        if let existing = pool[service.id] {
            return existing.webView
        }
        let swv = ServiceWebView(service: service, customUserAgent: appState.settings.customUserAgent,
                                 micCompatMode: appState.settings.micCompatMode,
                                 micGain: appState.settings.micGain,
                                 webInspector: appState.settings.webInspectorEnabled,
                                 adBlock: appState.settings.adBlockEnabled)
        swv.onNotify = { [weak self] id, title, body, iconURL in
            self?.handleNotify(serviceID: id, title: title, body: body, iconURL: iconURL)
        }
        swv.onBadge = { [weak self] id, count in
            self?.appState.setUnread(count, for: id)
        }
        pool[service.id] = swv
        publishAwake()
        return swv.webView
    }

    /// Wird beim Wechsel des aktiven Dienstes aufgerufen.
    func didSelect(_ selectedID: UUID?, allServices: [Service]) {
        for service in allServices {
            if service.id == selectedID { continue }
            guard pool[service.id] != nil else { continue }
            switch service.sleepPolicy {
            case .alwaysAwake:
                cancelSleep(service.id)
            case .sleepWhenInactive:
                scheduleSleep(service.id)
            }
        }
    }

    func reload(_ id: UUID) { pool[id]?.reload() }

    func fill(serviceID: UUID, username: String, password: String) {
        pool[serviceID]?.fillLogin(username: username, password: password)
    }

    func applyZoom(_ zoom: Double, to id: UUID) { pool[id]?.applyZoom(zoom) }

    func isAwake(_ id: UUID) -> Bool { pool[id] != nil }

    /// Ein Dienst gilt als „schlafend“, wenn er nicht geladen ist und nicht der
    /// gerade aktive Dienst ist. So sieht der Nutzer eindeutig, was im Hintergrund
    /// entladen wurde bzw. noch nicht geladen wurde.
    func isSleeping(_ id: UUID, selected: UUID?) -> Bool {
        id != selected && pool[id] == nil
    }

    /// Lädt alle „immer wach“-Dienste schon beim Start in den Hintergrund, damit
    /// Benachrichtigungen sofort kommen, ohne dass man sie erst öffnen muss.
    func preloadAlwaysAwake() {
        for service in appState.services where service.sleepPolicy == .alwaysAwake {
            _ = webView(for: service)   // erzeugt + lädt die WebView im Hintergrund
        }
    }

    /// Lädt eine URL im (bei Bedarf erzeugten) WebView eines Dienstes –
    /// z.B. wenn ein Link von außen an den Dienst übergeben wird.
    func load(urlString: String, into service: Service) {
        _ = webView(for: service)        // sicherstellen, dass er wach ist
        pool[service.id]?.load(urlString: urlString)
    }

    /// Dienst sofort schlafen legen (ohne auf das Timeout zu warten).
    func sleepNow(_ id: UUID) {
        discard(id)
    }

    /// WebView vollständig entfernen (z.B. wenn Dienst gelöscht wird oder schläft).
    func discard(_ id: UUID) {
        cancelSleep(id)
        if let swv = pool[id] {
            swv.webView.stopLoading()
            swv.webView.navigationDelegate = nil
            swv.webView.uiDelegate = nil
        }
        pool[id] = nil
        publishAwake()
    }

    /// Alle WebViews verwerfen – damit geänderte Einstellungen (User-Agent,
    /// Mikrofon, Inspektor …) beim nächsten Anzeigen sofort greifen.
    func recreateAll(currentSelection: UUID?) {
        for id in Array(pool.keys) {
            cancelSleep(id)
            if let swv = pool[id] {
                swv.webView.stopLoading()
                swv.webView.navigationDelegate = nil
                swv.webView.uiDelegate = nil
            }
            pool[id] = nil
        }
        publishAwake()
    }

    /// Spiegelt `pool` nach `awakeIDs` – asynchron und nur bei echter Änderung,
    /// um Render-Endlosschleifen zu vermeiden.
    private func publishAwake() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let current = Set(self.pool.keys)
            if self.awakeIDs != current { self.awakeIDs = current }
        }
    }

    // MARK: Schlaf-Logik

    private func scheduleSleep(_ id: UUID) {
        cancelSleep(id)
        let delay = max(30, appState.settings.sleepDelaySeconds)
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.discard(id) }
        }
        sleepTimers[id] = timer
    }

    private func cancelSleep(_ id: UUID) {
        sleepTimers[id]?.invalidate()
        sleepTimers[id] = nil
    }

    // MARK: Benachrichtigungen

    private func handleNotify(serviceID: UUID, title: String, body: String, iconURL: String) {
        guard let service = appState.services.first(where: { $0.id == serviceID }) else { return }
        appState.bumpUnread(for: serviceID)

        // Globales DND, Stummschaltung, Schlummern oder Stil "aus" -> keine Benachrichtigung.
        if appState.settings.dndEnabled || service.muted || service.isSnoozed { return }
        // Ruhezeiten des zugehörigen Workspace.
        if let wsID = service.workspaceID,
           let ws = appState.workspaces.first(where: { $0.id == wsID }),
           ws.isQuietNow() { return }
        let style = service.notificationStyle
        if style == .off { return }
        // Stichwort-Filter (falls gesetzt).
        if !service.matchesNotificationFilter(title: title, body: body) { return }

        let fallback = service.iconData ?? service.faviconData
        NotificationManager.shared.post(
            serviceID: serviceID,
            serviceName: service.name,
            title: title.isEmpty ? service.name : title,
            body: body,
            iconURLString: iconURL,
            fallbackIcon: fallback,
            showBanner: style.showsBanner,
            playSound: style.playsSound
        )
    }
}
