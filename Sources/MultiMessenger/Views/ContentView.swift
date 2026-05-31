import SwiftUI

/// Welches modale Sheet gerade angezeigt wird. Ein einziges `.sheet(item:)`
/// statt mehrerer gestapelter Sheets – behebt das „erst beim zweiten Klick“-Problem.
enum ActiveSheet: Identifiable {
    case add
    case edit(Service)
    case settings

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let s): return "edit-\(s.id)"
        case .settings: return "settings"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: WebViewManager
    @EnvironmentObject var icons: IconCache

    @State private var activeSheet: ActiveSheet?
    /// Wird erhöht, um die aktuell sichtbare WebView neu zu erzeugen
    /// (z.B. nachdem Einstellungen geändert wurden).
    @State private var webRefresh = 0

    var body: some View {
        layout
            .background(.background)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add:
                    ServiceEditor(mode: .add).environmentObject(app).environmentObject(icons)
                case .edit(let service):
                    ServiceEditor(mode: .edit(service)).environmentObject(app).environmentObject(icons)
                case .settings:
                    SettingsView().environmentObject(app)
                }
            }
            .overlay {
                if app.showQuickSwitcher {
                    QuickSwitcher().environmentObject(app).environmentObject(icons)
                }
            }
            .sheet(isPresented: Binding(
                get: { app.pendingShareURL != nil },
                set: { if !$0 { app.pendingShareURL = nil } }
            )) {
                if let url = app.pendingShareURL {
                    ShareReceiverSheet(urlString: url)
                        .environmentObject(app).environmentObject(manager).environmentObject(icons)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadService)) { note in
                if let id = note.object as? UUID { manager.reload(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .discardService)) { note in
                if let id = note.object as? UUID {
                    manager.discard(id)
                    if id == app.selectedServiceID { webRefresh += 1 }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { _ in
                // Geänderte globale Einstellungen (User-Agent, Mikrofon, Inspektor)
                // sofort wirksam machen, ohne Neustart.
                manager.recreateAll(currentSelection: app.selectedServiceID)
                webRefresh += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .fillLogin)) { note in
                if let id = note.object as? UUID {
                    LoginFiller.fill(serviceID: id,
                                     requireBiometric: app.settings.requireBiometricForLogin,
                                     manager: manager)
                }
            }
            .onReceive(app.$selectedServiceID) { newValue in
                manager.didSelect(newValue, allServices: app.services)
            }
    }

    @ViewBuilder
    private var layout: some View {
        let strip = TabStrip(activeSheet: $activeSheet)
            .environmentObject(app)

        switch app.settings.tabBarPosition {
        case .left:
            HStack(spacing: 0) { strip; Divider(); webArea }
        case .right:
            HStack(spacing: 0) { webArea; Divider(); strip }
        case .top:
            VStack(spacing: 0) { strip; Divider(); webArea }
        case .bottom:
            VStack(spacing: 0) { webArea; Divider(); strip }
        }
    }

    @ViewBuilder
    private var webArea: some View {
        if let service = app.selectedService {
            if app.needsUnlock(service) {
                ServiceLockView(service: service).environmentObject(app)
            } else {
                WebContainer(service: service, manager: manager)
                    .id("\(service.id)-\(webRefresh)")
            }
        } else {
            EmptyState(activeSheet: $activeSheet)
        }
    }
}

private struct EmptyState: View {
    @EnvironmentObject var app: AppState
    @Binding var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.tint)
            Text(app.services.isEmpty ? "Willkommen bei MultiMessenger" : "Kein Dienst ausgewählt")
                .font(.title2.weight(.semibold))
            Text(app.services.isEmpty
                 ? "Füge deinen ersten Messenger oder deine erste Webseite hinzu."
                 : "Wähle links einen Dienst aus.")
                .foregroundStyle(.secondary)
            Button {
                activeSheet = .add
            } label: {
                Label("Dienst hinzufügen", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
