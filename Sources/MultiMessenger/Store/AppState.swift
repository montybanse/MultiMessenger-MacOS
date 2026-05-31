import Foundation
import SwiftUI
import Combine

/// Auf der Platte gespeicherter Zustand.
struct PersistedState: Codable {
    var services: [Service] = []
    var workspaces: [Workspace] = []
    var settings: AppSettings = AppSettings()
    var selectedServiceID: UUID? = nil
    var selectedWorkspaceID: UUID? = nil
}

@MainActor
final class AppState: ObservableObject {
    @Published var services: [Service] = []
    @Published var workspaces: [Workspace] = []
    @Published var settings: AppSettings = AppSettings()

    @Published var selectedServiceID: UUID?
    @Published var selectedWorkspaceID: UUID?   // nil = "Alle"

    /// Ungelesen-Zähler pro Dienst (nicht persistiert).
    @Published var unread: [UUID: Int] = [:]

    /// Sperrbildschirm aktiv?
    @Published var isLocked: Bool = false

    /// Quick-Switcher sichtbar?
    @Published var showQuickSwitcher: Bool = false

    /// Über das Teilen-Menü / URL-Schema hereingereichte URL, die der Nutzer
    /// einem Dienst zuordnen soll. Nicht-nil = Auswahldialog anzeigen.
    @Published var pendingShareURL: String?

    /// Pro Sitzung freigeschaltete (entsperrte) Dienste – nicht persistiert.
    @Published var unlockedServiceIDs: Set<UUID> = []

    private var saveCancellable: AnyCancellable?

    // MARK: Abgeleitete Daten

    var visibleServices: [Service] {
        guard let ws = selectedWorkspaceID else { return services }
        return services.filter { $0.workspaceID == ws }
    }

    var selectedService: Service? {
        guard let id = selectedServiceID else { return nil }
        return services.first { $0.id == id }
    }

    var totalUnread: Int {
        unread.values.reduce(0, +)
    }

    // MARK: Lebenszyklus

    init() {
        load()
        if settings.lockEnabled {
            isLocked = true
        }
        // Debounced automatisches Speichern bei Änderungen.
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
    }

    // MARK: Dienste verwalten

    func addService(_ service: Service) {
        var s = service
        if s.workspaceID == nil { s.workspaceID = selectedWorkspaceID }
        services.append(s)
        selectedServiceID = s.id
    }

    func updateService(_ service: Service) {
        guard let idx = services.firstIndex(where: { $0.id == service.id }) else { return }
        services[idx] = service
    }

    func removeService(_ id: UUID) {
        services.removeAll { $0.id == id }
        unread[id] = nil
        if selectedServiceID == id {
            selectedServiceID = visibleServices.first?.id
        }
    }

    /// Verschiebt einen Dienst per Drag&Drop direkt vor einen anderen.
    func move(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = services.firstIndex(where: { $0.id == id }) else { return }
        let moving = services.remove(at: from)
        if let to = services.firstIndex(where: { $0.id == targetID }) {
            services.insert(moving, at: to)
        } else {
            services.append(moving)
        }
    }

    func select(_ id: UUID) {
        selectedServiceID = id
        unread[id] = 0   // Beim Ansehen als gelesen markieren
    }

    func selectIndex(_ index: Int) {
        let list = visibleServices
        guard index >= 0, index < list.count else { return }
        select(list[index].id)
    }

    // MARK: Workspaces

    func addWorkspace(_ ws: Workspace) {
        workspaces.append(ws)
    }

    func removeWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        // Dienste dieses Workspace ohne Zuordnung lassen.
        for i in services.indices where services[i].workspaceID == id {
            services[i].workspaceID = nil
        }
        if selectedWorkspaceID == id { selectedWorkspaceID = nil }
    }

    // MARK: Ungelesen

    func setUnread(_ count: Int, for id: UUID) {
        if id == selectedServiceID { return } // aktiver Dienst gilt als gelesen
        unread[id] = count
    }

    func bumpUnread(for id: UUID) {
        if id == selectedServiceID { return }
        unread[id, default: 0] += 1
    }

    // MARK: Persistenz

    /// Ordner für die App-Daten (außerhalb des App-Bundles -> überlebt Updates).
    private static var storeDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MultiMessenger", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var storeURL: URL {
        storeDirectory.appendingPathComponent("store.json")
    }

    /// true, sobald erfolgreich (oder bei Erststart) geladen wurde. Schützt davor,
    /// dass ein fehlgeschlagenes Laden anschließend leere Daten überschreibt.
    private var didLoadSuccessfully = false

    func load() {
        let url = Self.storeURL
        // Schutz: Falls versehentlich ein Ordner an dieser Stelle liegt -> entfernen.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(at: url)
            didLoadSuccessfully = true   // war nie eine gültige Datei -> Speichern erlaubt
            return
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            // Keine/leere Datei (Erststart) -> Speichern erlaubt.
            didLoadSuccessfully = true
            return
        }

        do {
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            apply(decoded)
            didLoadSuccessfully = true
        } catch {
            // Datei vorhanden, aber nicht lesbar: NICHT überschreiben! Kopie sichern
            // und Speichern sperren, bis das Problem behoben ist.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("AppState.load: store.json nicht lesbar (\(error)). Sicherung: \(backup.lastPathComponent). Speichern gesperrt.")
            didLoadSuccessfully = false
        }
    }

    private func apply(_ decoded: PersistedState) {
        services = decoded.services
        workspaces = decoded.workspaces
        settings = decoded.settings
        selectedWorkspaceID = decoded.selectedWorkspaceID
        selectedServiceID = decoded.selectedServiceID ?? services.first?.id
    }

    private var snapshot: PersistedState {
        PersistedState(
            services: services,
            workspaces: workspaces,
            settings: settings,
            selectedServiceID: selectedServiceID,
            selectedWorkspaceID: selectedWorkspaceID
        )
    }

    func save() {
        // Sicherheitssperre: nach fehlgeschlagenem Laden NICHT speichern.
        guard didLoadSuccessfully else {
            NSLog("AppState.save: übersprungen (Laden war fehlgeschlagen, Daten geschützt).")
            return
        }

        let url = Self.storeURL
        // Schutz: liegt hier (fälschlich) ein Ordner, erst entfernen.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(at: url)
        }

        // Zusatzschutz: keine leere Dienstliste über eine vorhandene, nicht-leere
        // Datei schreiben (verhindert versehentliches „alles weg").
        if services.isEmpty, let existing = try? Data(contentsOf: url),
           let prev = try? JSONDecoder().decode(PersistedState.self, from: existing),
           !prev.services.isEmpty {
            NSLog("AppState.save: übersprungen (leere Liste würde \(prev.services.count) Dienste überschreiben).")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(snapshot) else { return }

        // Vor dem Überschreiben rollierende Sicherung anlegen.
        if let existing = try? Data(contentsOf: url), !existing.isEmpty {
            let bak = url.deletingPathExtension().appendingPathExtension("bak.json")
            try? existing.write(to: bak, options: .atomic)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("AppState.save Fehler: \(error.localizedDescription)")
        }
    }

    // MARK: Backup (Export / Import)

    /// Exportiert die gesamte Konfiguration als JSON-Daten.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try? encoder.encode(snapshot)
    }

    /// Importiert eine zuvor exportierte Konfiguration.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return false
        }
        apply(decoded)
        save()
        return true
    }

    var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Muss der Dienst noch per Touch ID entsperrt werden, bevor er sichtbar wird?
    func needsUnlock(_ service: Service) -> Bool {
        service.locked && !unlockedServiceIDs.contains(service.id)
    }

    func markUnlocked(_ id: UUID) {
        unlockedServiceIDs.insert(id)
    }

    /// Akzentfarbe des aktiven Workspace (nil = System-Akzent).
    /// Bei "Alle Dienste" wird der Workspace des ausgewählten Dienstes genutzt.
    var currentAccent: Color? {
        let wsID = selectedWorkspaceID ?? selectedService?.workspaceID
        guard let wsID,
              let ws = workspaces.first(where: { $0.id == wsID }) else { return nil }
        return AccentPalette.color(for: ws.accentKey)
    }
}
