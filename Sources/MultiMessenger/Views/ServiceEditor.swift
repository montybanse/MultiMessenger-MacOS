import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ServiceEditor: View {
    enum Mode {
        case add
        case edit(Service)
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var draft: Service
    @State private var showCatalog: Bool
    @State private var catalogSearch = ""

    @State private var loginUser = ""
    @State private var loginPass = ""
    @State private var loginStored = false

    @State private var showResetConfirm = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _draft = State(initialValue: Service(name: "", urlString: ""))
            _showCatalog = State(initialValue: true)
        case .edit(let service):
            _draft = State(initialValue: service)
            _showCatalog = State(initialValue: false)
        }
    }

    var isEditing: Bool { if case .edit = mode { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showCatalog {
                catalogView
            } else {
                formView
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Dienst bearbeiten" : (showCatalog ? "Dienst wählen" : "Eigener Dienst"))
                .font(.headline)
            Spacer()
            if !isEditing {
                Picker("", selection: $showCatalog) {
                    Text("Vorlagen").tag(true)
                    Text("Eigene URL").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
            }
        }
        .padding()
    }

    // MARK: Vorlagen-Katalog

    private var catalogView: some View {
        VStack(spacing: 0) {
            TextField("Suchen …", text: $catalogSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal).padding(.vertical, 8)

            ScrollView {
                ForEach(ServiceCatalog.categories, id: \.self) { category in
                    let items = filteredTemplates(in: category)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(items) { template in
                                    Button { pick(template) } label: { templateCell(template) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    private func filteredTemplates(in category: String) -> [ServiceTemplate] {
        ServiceCatalog.all.filter {
            $0.category == category &&
            (catalogSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(catalogSearch))
        }
    }

    private func templateCell(_ template: ServiceTemplate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: template.symbol)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(template.name).lineLimit(1)
            Spacer()
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pick(_ template: ServiceTemplate) {
        draft.name = template.name
        draft.urlString = template.urlString
        draft.iconSymbol = template.symbol
        draft.templateID = template.id
        showCatalog = false
    }

    // MARK: Formular

    private var formView: some View {
        Form {
            Section("Allgemein") {
                TextField("Name", text: $draft.name)
                TextField("URL", text: $draft.urlString, prompt: Text("https://…"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                if !app.workspaces.isEmpty {
                    Picker("Workspace", selection: workspaceBinding) {
                        Text("— kein —").tag(UUID?.none)
                        ForEach(app.workspaces) { ws in
                            Text(ws.name).tag(UUID?.some(ws.id))
                        }
                    }
                }
            }

            Section("Verhalten") {
                Picker("Schlafmodus", selection: $draft.sleepPolicy) {
                    ForEach(SleepPolicy.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Stummschalten (keine Benachrichtigungen)", isOn: $draft.muted)
                HStack {
                    Text("Zoom")
                    Slider(value: $draft.zoom, in: 0.5...2.0, step: 0.1)
                    Text("\(Int(draft.zoom * 100)) %").monospacedDigit().frame(width: 50)
                }
            }

            Section {
                Picker("Benachrichtigungen", selection: $draft.notificationStyle) {
                    ForEach(NotificationStyle.allCases) { Text($0.label).tag($0) }
                }
                .disabled(draft.muted)
                TextField("Nur bei Stichwort (kommagetrennt, optional)",
                          text: $draft.notificationKeywords)
                    .disabled(draft.muted || draft.notificationStyle == .off)
            } header: {
                Text("Benachrichtigungsregeln")
            } footer: {
                Text(draft.muted
                     ? "Dieser Dienst ist stummgeschaltet – es kommen keine Benachrichtigungen."
                     : "Stichwörter: z. B. „@monty, dringend“ → es wird nur benachrichtigt, wenn eines davon im Titel/Text vorkommt. Leer = alle Nachrichten.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Dienst mit Touch ID / Passwort schützen", isOn: Binding(
                    get: { draft.locked },
                    set: { newValue in
                        if !newValue && draft.locked {
                            // Abschalten nur nach erfolgreicher Authentifizierung –
                            // sonst ließe sich die Sperre einfach wegklicken.
                            BiometricAuth.authenticate(reason: "den Schutz von „\(draft.name)“ aufzuheben") { ok in
                                if ok { draft.locked = false }
                            }
                        } else {
                            draft.locked = newValue
                        }
                    }
                ))
            } footer: {
                Text("Beim Öffnen dieses Dienstes wird eine Entsperrung verlangt – praktisch für private Accounts.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Browser-Kennung", selection: uaPresetBinding) {
                    Text("Standard (Safari)").tag(0)
                    Text("Chrome").tag(1)
                    Text("Eigene …").tag(2)
                }
                if uaPreset == 2 {
                    TextField("User-Agent", text: $draft.userAgent)
                        .font(.system(.caption, design: .monospaced))
                }
            } header: {
                Text("Kompatibilität")
            } footer: {
                Text("Mit welcher Browser-Kennung sich der Dienst meldet. Bei Problemen umschalten: Slack, MS Teams und BigBlueButton (virtueller Hintergrund) brauchen „Chrome“; WhatsApp & die meisten anderen laufen am besten mit „Standard“. Nach dem Wechsel den Dienst neu laden (⌘R).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Icon") {
                HStack {
                    ServiceIconView(service: draft, size: 40)
                    Spacer()
                    Button("Bild wählen …") { chooseIcon() }
                    if draft.iconData != nil {
                        Button("Entfernen") { draft.iconData = nil }
                    }
                }
                Toggle("Favicon der Seite verwenden", isOn: $draft.useFavicon)
            }

            Section {
                TextField("Benutzername / E-Mail", text: $loginUser)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField(loginStored ? "•••••• (leer lassen, um zu behalten)" : "Passwort",
                            text: $loginPass)
                if loginStored {
                    Button("Gespeicherte Anmeldedaten löschen", role: .destructive) {
                        CredentialStore.delete(draft.id)
                        loginStored = false; loginUser = ""; loginPass = ""
                    }
                }
            } header: {
                Text("Anmeldung (Schlüsselbund)")
            } footer: {
                Text("Sicher im Schlüsselbund gespeichert (iCloud-Sync, sobald signiert). Ausfüllen per ⌘⇧L oder Rechtsklick auf den Dienst.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if isEditing {
                Section {
                    Button("Website-Daten löschen & neu anmelden …", role: .destructive) {
                        showResetConfirm = true
                    }
                    .confirmationDialog(
                        "Website-Daten von „\(draft.name)“ löschen?",
                        isPresented: $showResetConfirm, titleVisibility: .visible
                    ) {
                        Button("Daten löschen", role: .destructive) { resetWebsiteData() }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Entfernt Cookies, Cache und alle gespeicherten Website-Daten dieses Dienstes – du wirst abgemeldet und kannst dich frisch verbinden (z.B. WhatsApp neu koppeln). Die Dienst-Einstellungen und Schlüsselbund-Anmeldedaten bleiben erhalten.")
                    }
                } header: {
                    Text("Zurücksetzen")
                } footer: {
                    Text("Hilft, wenn ein Dienst hängt oder die Anmeldung kaputt ist.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Erweitert") {
                VStack(alignment: .leading) {
                    Text("Eigenes CSS").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.customCSS)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 60)
                        .border(.quaternary)
                }
                VStack(alignment: .leading) {
                    Text("Eigenes JavaScript").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.customJS)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 60)
                        .border(.quaternary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCredentials)
    }

    /// Setzt die Website-Daten des Dienstes zurück: Der Dienst bekommt einen
    /// frischen (garantiert leeren) Datenspeicher, der alte wird im Hintergrund
    /// gelöscht. Der Umweg über eine neue dataStoreID vermeidet Konflikte mit
    /// einem evtl. noch geöffneten Speicher.
    private func resetWebsiteData() {
        let oldStoreID = draft.dataStoreID
        draft.dataStoreID = UUID()
        app.updateService(draft)
        // Laufende WebView verwerfen -> wird mit dem neuen, leeren Speicher
        // neu erzeugt (Login-Seite erscheint).
        NotificationCenter.default.post(name: .discardService, object: draft.id)
        // Alte Daten (Cookies, Cache, IndexedDB …) entfernen, sobald die
        // WebView den Speicher freigegeben hat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            WKWebsiteDataStore.remove(forIdentifier: oldStoreID) { error in
                if let error {
                    NSLog("Website-Daten-Reset: Löschen des alten Speichers: \(error.localizedDescription)")
                }
            }
        }
        dismiss()
    }

    private func loadCredentials() {
        guard !loginStored, loginUser.isEmpty else { return }
        if let cred = CredentialStore.load(draft.id) {
            loginUser = cred.username
            loginStored = true
        }
    }

    private var workspaceBinding: Binding<UUID?> {
        Binding(get: { draft.workspaceID }, set: { draft.workspaceID = $0 })
    }

    private var uaPreset: Int {
        let ua = draft.userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if ua.isEmpty { return 0 }
        if ua == UserAgentPreset.chrome { return 1 }
        return 2
    }

    private var uaPresetBinding: Binding<Int> {
        Binding(
            get: { uaPreset },
            set: { newValue in
                switch newValue {
                case 0: draft.userAgent = ""
                case 1: draft.userAgent = UserAgentPreset.chrome
                default:
                    if draft.userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.userAgent == UserAgentPreset.chrome {
                        draft.userAgent = UserAgentPreset.safari
                    }
                }
            }
        )
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            draft.iconData = data
        }
    }

    // MARK: Fußzeile

    private var footer: some View {
        HStack {
            if showCatalog {
                Button("Eigene URL …") { showCatalog = false }
            }
            Spacer()
            Button("Abbrechen") { dismiss() }
            Button(isEditing ? "Speichern" : "Hinzufügen") { commit() }
                .keyboardShortcut(.defaultAction)
                .disabled(showCatalog || draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                          || draft.urlString.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func commit() {
        if isEditing {
            app.updateService(draft)
            // Dienst neu erzeugen, damit geänderte Browser-Kennung / CSS / JS greifen.
            NotificationCenter.default.post(name: .discardService, object: draft.id)
        } else {
            app.addService(draft)
        }
        saveCredentials()
        dismiss()
    }

    private func saveCredentials() {
        let user = loginUser.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nichts eingegeben und nichts gespeichert -> nichts tun.
        if user.isEmpty && loginPass.isEmpty && !loginStored { return }
        if user.isEmpty && loginPass.isEmpty { return }

        var pass = loginPass
        if pass.isEmpty, let existing = CredentialStore.load(draft.id) {
            pass = existing.password   // vorhandenes Passwort beibehalten
        }
        CredentialStore.save(LoginCredential(username: user, password: pass), for: draft.id)
    }
}
