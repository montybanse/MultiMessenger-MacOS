import SwiftUI

/// Die Dienst-Leiste. Funktioniert sowohl vertikal (links/rechts) als auch
/// horizontal (oben/unten).
struct TabStrip: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: WebViewManager
    @Binding var activeSheet: ActiveSheet?

    var vertical: Bool { app.settings.tabBarPosition.isVertical }

    var body: some View {
        Group {
            if vertical {
                VStack(spacing: 6) {
                    workspaceSwitcher
                    Divider().padding(.horizontal, 10)
                    serviceList
                    Spacer(minLength: 0)
                    controls
                }
                // Oben Platz für die Fenster-Ampeln lassen, wenn links angedockt.
                .padding(.top, app.settings.tabBarPosition == .left ? 30 : 10)
                .padding(.bottom, 10)
                .frame(width: 64)
            } else {
                HStack(spacing: 6) {
                    workspaceSwitcher
                    Divider().frame(height: 30)
                    serviceList
                    Spacer(minLength: 0)
                    controls
                }
                // Links Platz für die Fenster-Ampeln lassen, wenn oben angedockt.
                .padding(.leading, app.settings.tabBarPosition == .top ? 76 : 10)
                .padding(.trailing, 10)
                .frame(height: 56)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Workspaces

    @ViewBuilder
    private var workspaceSwitcher: some View {
        if app.workspaces.isEmpty {
            EmptyView()
        } else {
            Menu {
                Button {
                    app.selectedWorkspaceID = nil
                } label: {
                    Label("Alle Dienste", systemImage: "square.grid.2x2")
                }
                Divider()
                ForEach(app.workspaces) { ws in
                    Button {
                        app.selectedWorkspaceID = ws.id
                        app.selectedServiceID = app.visibleServices.first?.id
                    } label: {
                        Label(ws.name, systemImage: ws.symbol)
                    }
                }
            } label: {
                Image(systemName: currentWorkspaceSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 32, height: 32)
            .help("Workspace wechseln")
        }
    }

    private var currentWorkspaceSymbol: String {
        guard let id = app.selectedWorkspaceID,
              let ws = app.workspaces.first(where: { $0.id == id }) else {
            return "square.grid.2x2"
        }
        return ws.symbol
    }

    // MARK: Dienste

    @ViewBuilder
    private var serviceList: some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
            layout {
                ForEach(Array(app.visibleServices.enumerated()), id: \.element.id) { index, service in
                    TabItem(
                        service: service,
                        index: index,
                        isSelected: service.id == app.selectedServiceID,
                        unread: app.unread[service.id] ?? 0,
                        sleeping: manager.isSleeping(service.id, selected: app.selectedServiceID)
                    )
                    .environmentObject(app)
                    .contextMenu { contextMenu(for: service) }
                    .onTapGesture { app.select(service.id) }
                    .draggable(service.id.uuidString) {
                        ServiceIconView(service: service, size: 34)
                            .environmentObject(app)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first, let dragged = UUID(uuidString: first) else { return false }
                        app.move(id: dragged, before: service.id)
                        return true
                    }
                }
            }
            .padding(vertical ? .vertical : .horizontal, 2)
        }
    }

    @ViewBuilder
    private func contextMenu(for service: Service) -> some View {
        if CredentialStore.has(service.id) {
            Button("Anmeldedaten ausfüllen") {
                NotificationCenter.default.post(name: .fillLogin, object: service.id)
            }
            Divider()
        }
        Button("Neu laden") { NotificationCenter.default.post(name: .reloadService, object: service.id) }
        if manager.isAwake(service.id) {
            Button("Jetzt schlafen legen") { manager.sleepNow(service.id) }
        } else if service.id != app.selectedServiceID {
            Button("Jetzt aufwecken") { app.select(service.id) }
        }
        Button(service.muted ? "Stummschaltung aufheben" : "Stummschalten") {
            var s = service; s.muted.toggle(); app.updateService(s)
        }
        Divider()
        Button("Bearbeiten …") { activeSheet = .edit(service) }
        Divider()
        Button("Entfernen", role: .destructive) {
            NotificationCenter.default.post(name: .discardService, object: service.id)
            app.removeService(service.id)
        }
    }

    // MARK: Steuerung (Hinzufügen / Einstellungen)

    private var controls: some View {
        Group {
            let layout = vertical
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Button { app.settings.dndEnabled.toggle() } label: {
                    Image(systemName: app.settings.dndEnabled ? "moon.fill" : "bell.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(app.settings.dndEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(app.settings.dndEnabled ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .help(app.settings.dndEnabled
                      ? "Nicht stören ist AN – alle Benachrichtigungen aus. Klicken zum Aktivieren."
                      : "Alle Dienste stummschalten (Nicht stören)")

                Button { activeSheet = .add } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .help("Dienst hinzufügen")

                Button { activeSheet = .settings } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Einstellungen")
            }
        }
    }
}

/// Einzelnes Dienst-Icon in der Leiste.
private struct TabItem: View {
    @EnvironmentObject var app: AppState
    let service: Service
    let index: Int
    let isSelected: Bool
    let unread: Int
    var sleeping: Bool = false

    var body: some View {
        ServiceIconView(service: service, size: 34, unread: unread,
                        muted: service.muted, sleeping: sleeping, locked: service.locked)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            }
            .overlay(alignment: .leading) {
                if isSelected && app.settings.tabBarPosition == .left {
                    Capsule().fill(.tint).frame(width: 3, height: 22).offset(x: -7)
                }
            }
            .help(service.name + (index < 9 ? "  (⌘\(index + 1))" : ""))
            .contentShape(Rectangle())
    }
}

extension Notification.Name {
    static let reloadService = Notification.Name("mm.reloadService")
    static let discardService = Notification.Name("mm.discardService")
    static let selectServiceIndex = Notification.Name("mm.selectServiceIndex")
    static let fillLogin = Notification.Name("mm.fillLogin")
    static let settingsChanged = Notification.Name("mm.settingsChanged")
}
