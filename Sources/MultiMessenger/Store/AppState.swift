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

    func load() {
        let url = Self.storeURL
        // Schutz: Falls versehentlich ein Ordner an dieser Stelle liegt -> entfernen.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        apply(decoded)
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
        let url = Self.storeURL
        // Schutz: liegt hier (fälschlich) ein Ordner, erst entfernen.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(at: url)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(snapshot) else { return }
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
}
