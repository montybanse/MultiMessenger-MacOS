import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var importMessage: String?
    @StateObject private var micMeter = MicLevelMeter()
    @StateObject private var webMic = WebMicTester()
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab.tabItem { Label("Allgemein", systemImage: "gearshape") }
                notificationsTab.tabItem { Label("Mitteilungen", systemImage: "bell") }
                workspacesTab.tabItem { Label("Workspaces", systemImage: "square.grid.2x2") }
                advancedTab.tabItem { Label("Erweitert", systemImage: "slider.horizontal.3") }
                backupTab.tabItem { Label("Sicherung", systemImage: "externaldrive") }
                aboutTab.tabItem { Label("Über", systemImage: "info.circle") }
            }
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 480)
        .onDisappear {
            micMeter.stop()
            webMic.stop()
            // Geänderte Einstellungen sofort auf die Dienste anwenden.
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: Allgemein

    private var generalTab: some View {
        Form {
            Section("Darstellung") {
                Picker("Tableiste", selection: settingBinding(\.tabBarPosition)) {
                    ForEach(TabBarPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Erscheinungsbild", selection: settingBinding(\.appearance)) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Start") {
                Toggle("Beim Anmelden starten", isOn: Binding(
                    get: { app.settings.startAtLogin },
                    set: { app.settings.startAtLogin = $0; LoginItem.setEnabled($0) }
                ))
                Toggle("Im Hintergrund weiterlaufen (Fenster schließen beendet nicht)",
                       isOn: settingBinding(\.keepRunningInBackground))
                Toggle("Beim Start auf Updates prüfen (GitHub)",
                       isOn: settingBinding(\.updateCheckEnabled))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Mitteilungen

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Nicht stören (alle Benachrichtigungen aus)", isOn: settingBinding(\.dndEnabled))
            } footer: {
                Text("Einzelne Dienste lassen sich über das Kontextmenü stummschalten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    NotificationManager.shared.postTest()
                } label: {
                    Label("Testbenachrichtigung senden", systemImage: "bell.badge")
                }
            } footer: {
                Text("Zeigt sofort eine Beispiel-Mitteilung – praktisch, um Berechtigung und Darstellung zu prüfen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hinweis") {
                Text("Damit Benachrichtigungen erscheinen, muss MultiMessenger in den Systemeinstellungen unter „Mitteilungen“ erlaubt sein.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Workspaces

    @State private var newWorkspaceName = ""

    private var workspacesTab: some View {
        Form {
            Section {
                if app.workspaces.isEmpty {
                    Text("Noch keine Workspaces angelegt.").foregroundStyle(.secondary)
                } else {
                    ForEach(app.workspaces) { ws in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: ws.symbol)
                                    .foregroundStyle(AccentPalette.color(for: ws.accentKey) ?? .secondary)
                                Text(ws.name)
                                Spacer()
                                accentMenu(for: ws)
                                Button(role: .destructive) { app.removeWorkspace(ws.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            quietHoursRow(for: ws)
                        }
                    }
                }
            } header: {
                Text("Vorhandene Workspaces")
            } footer: {
                Text("Ruhezeiten unterdrücken Benachrichtigungen aller Dienste des Workspace im gewählten Zeitfenster – z.B. berufliche Dienste abends, private tagsüber.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    TextField("Name", text: $newWorkspaceName)
                    Button("Anlegen") {
                        let trimmed = newWorkspaceName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        app.addWorkspace(Workspace(name: trimmed))
                        newWorkspaceName = ""
                    }
                    .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Neuer Workspace")
            } footer: {
                Text("Tipp: Gib jedem Workspace eine eigene Akzentfarbe (über das Farbmenü) – die Oberfläche färbt sich dann passend, sobald der Workspace aktiv ist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Farb-Auswahlmenü für einen Workspace.
    private func accentMenu(for ws: Workspace) -> some View {
        Menu {
            Button {
                updateWorkspaceAccent(ws, key: nil)
            } label: {
                Label("System-Akzent", systemImage: ws.accentKey == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(AccentPalette.options, id: \.key) { opt in
                Button {
                    updateWorkspaceAccent(ws, key: opt.key)
                } label: {
                    Label(opt.label, systemImage: ws.accentKey == opt.key ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(AccentPalette.color(for: ws.accentKey) ?? .gray)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.quaternary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Akzentfarbe wählen")
    }

    private func updateWorkspaceAccent(_ ws: Workspace, key: String?) {
        guard let idx = app.workspaces.firstIndex(where: { $0.id == ws.id }) else { return }
        app.workspaces[idx].accentKey = key
    }

    /// Ruhezeiten-Zeile unter jedem Workspace (Toggle + von/bis-Uhrzeit).
    private func quietHoursRow(for ws: Workspace) -> some View {
        HStack(spacing: 8) {
            Toggle("Ruhezeiten", isOn: Binding(
                get: { ws.quietHoursEnabled },
                set: { var w = ws; w.quietHoursEnabled = $0; app.updateWorkspace(w) }
            ))
            .toggleStyle(.checkbox)
            if ws.quietHoursEnabled {
                DatePicker("von", selection: quietBinding(ws, \.quietStartMinutes),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
                Text("–").foregroundStyle(.secondary)
                DatePicker("bis", selection: quietBinding(ws, \.quietEndMinutes),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
                if ws.quietStartMinutes > ws.quietEndMinutes {
                    Text("(über Nacht)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.leading, 24)
    }

    /// Wandelt Minuten-seit-Mitternacht in ein Date für den DatePicker um (und zurück).
    private func quietBinding(_ ws: Workspace, _ keyPath: WritableKeyPath<Workspace, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = ws[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                var w = ws
                w[keyPath: keyPath] = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                app.updateWorkspace(w)
            }
        )
    }

    // MARK: Erweitert

    private var advancedTab: some View {
        Form {
            Section("Leistung") {
                VStack(alignment: .leading) {
                    Text("Inaktive Dienste schlafen legen nach: \(Int(app.settings.sleepDelaySeconds / 60)) Min.")
                    Slider(value: settingBinding(\.sleepDelaySeconds), in: 60...1800, step: 60)
                }
            }
            Section("Sicherheit & Bedienung") {
                Toggle("App mit Touch ID / Passwort sperren", isOn: Binding(
                    get: { app.settings.lockEnabled },
                    set: { app.settings.lockEnabled = $0 }
                ))
                Toggle("Globaler Hotkey (⌘⇧M) zum Hervorholen", isOn: Binding(
                    get: { app.settings.globalHotkeyEnabled },
                    set: {
                        app.settings.globalHotkeyEnabled = $0
                        if $0 { HotKeyManager.shared.register() } else { HotKeyManager.shared.unregister() }
                    }
                ))
            }
            Section {
                Toggle("Mikrofon-Kompatibilitätsmodus", isOn: settingBinding(\.micCompatMode))
                if app.settings.micCompatMode {
                    VStack(alignment: .leading) {
                        Text("Mikrofon-Lautstärke: \(Int(app.settings.micGain * 100)) %")
                        Slider(value: settingBinding(\.micGain), in: 1.0...5.0, step: 0.5)
                    }
                }
            } footer: {
                Text("Sorgt dafür, dass das eingebaute Mac-Mikrofon in Videoanrufen (BigBlueButton, Meet …) funktioniert; der Regler hebt den Pegel an. Nur abschalten, falls Gesprächspartner bei Lautsprecher-Nutzung ein Echo hören (oder Kopfhörer verwenden). Nach Änderungen den Dienst neu laden (⌘R).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                // Test 1: direkt am System (ohne WebKit).
                HStack {
                    Button {
                        micMeter.running ? micMeter.stop() : micMeter.start()
                    } label: {
                        Label(micMeter.running ? "System-Test beenden" : "System-Test starten",
                              systemImage: micMeter.running ? "stop.circle" : "mic.badge.plus")
                    }
                    if micMeter.running {
                        Text(micMeter.deviceName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if micMeter.running {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: micMeter.level)
                            .tint(micMeter.level > 0.25 ? .green : .orange)
                        Text(micMeter.peak > 0.3
                             ? "Signal kommt an – Spitze \(Int(micMeter.peak * 100)) %. Das Mikrofon funktioniert auf Systemebene."
                             : "Sprich jetzt: Schlägt der Balken kaum aus, liefert schon macOS zu wenig Pegel → Systemeinstellungen → Ton → Eingabe prüfen (Eingangslautstärke!).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !micMeter.errorText.isEmpty {
                    Text(micMeter.errorText).font(.caption).foregroundStyle(.red)
                }

                // Test 2: durch die Web-Ansicht (genau die Kette, die BBB & Co. nutzen).
                HStack {
                    Button {
                        webMic.running
                            ? webMic.stop()
                            : webMic.start(micCompatMode: app.settings.micCompatMode,
                                           micGain: app.settings.micGain)
                    } label: {
                        Label(webMic.running ? "Web-Test beenden" : "Web-Test starten",
                              systemImage: webMic.running ? "stop.circle" : "network.badge.shield.half.filled")
                    }
                    if webMic.running && !webMic.trackLabel.isEmpty {
                        Text(webMic.trackLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if webMic.running {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: webMic.level)
                            .tint(webMic.level > 0.25 ? .green : .orange)
                        Text(webMic.peak > 0.3
                             ? "Web-Ansicht erhält Signal – Spitze \(Int(webMic.peak * 100)) %. So sollte es auch in BBB funktionieren."
                             : "Sprich jetzt: Bleibt der Balken still, obwohl der System-Test ausschlägt, blockiert WebKit das Mikro → Kompatibilitätsmodus oben an/aus testen und Web-Test neu starten.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !webMic.errorText.isEmpty {
                    Text("Web-Test: \(webMic.errorText)").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Mikrofon-Test")
            } footer: {
                Text("System-Test misst direkt am Mac, Web-Test durch die Browser-Technik (wie in BBB, inkl. Kompatibilitätsmodus). Schlägt nur der System-Test aus, liegt es an WebKit – dann den Kompatibilitätsmodus aktivieren und den Web-Test wiederholen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Werbung & Tracker blockieren", isOn: settingBinding(\.adBlockEnabled))
            } header: {
                Text("Datenschutz")
            } footer: {
                Text("Blockiert bekannte Werbe- und Tracking-Netzwerke nativ über WebKit-Inhaltsregeln (kostet praktisch keine Leistung, spart Daten). Bewusst konservative Liste, damit Login- und Chatfunktionen nicht brechen. Greift nach dem Schließen der Einstellungen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Netzwerk") {
                VStack(alignment: .leading) {
                    Text("Eigener User-Agent (optional)").font(.caption).foregroundStyle(.secondary)
                    TextField("leer = Safari-Standard", text: settingBinding(\.customUserAgent))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            Section {
                Toggle("Web-Inspektor aktivieren", isOn: settingBinding(\.webInspectorEnabled))
            } footer: {
                Text("Zur Fehlersuche: Rechtsklick auf eine Seite → „Element-Informationen einblenden“ öffnet die Entwicklerkonsole. Nach dem Aktivieren den Dienst neu laden (⌘R).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Sicherung (Backup)

    private var backupTab: some View {
        Form {
            Section {
                Text("Deine Dienste, Workspaces und Einstellungen liegen unter „~/Library/Application Support/MultiMessenger“ und bleiben bei App-Updates erhalten. Logins (Cookies) liegen separat im WebKit-Speicher und bleiben ebenfalls erhalten.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Wo liegen meine Daten?")
            }

            Section {
                Button {
                    exportConfig()
                } label: {
                    Label("Konfiguration exportieren …", systemImage: "square.and.arrow.up")
                }
                Button {
                    importConfig()
                } label: {
                    Label("Konfiguration importieren …", systemImage: "square.and.arrow.down")
                }
                if let importMessage {
                    Text(importMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Exportiert eine .json-Datei mit allen Diensten und Einstellungen (ohne Passwörter/Cookies). Praktisch zum Übertragen auf einen anderen Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportConfig() {
        guard let data = app.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MultiMessenger-Backup.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            importMessage = "Exportiert nach \(url.lastPathComponent)."
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            if app.importData(data) {
                importMessage = "Import erfolgreich – \(app.services.count) Dienste geladen."
            } else {
                importMessage = "Import fehlgeschlagen: ungültige Datei."
            }
        }
    }

    // MARK: Über

    private static let repoURL = "https://github.com/montybanse/MultiMessenger-MacOS"

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (Build \(b))"
    }

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MultiMessenger").font(.title2.weight(.semibold))
                        Text(appVersion).font(.caption).foregroundStyle(.secondary)
                        Text("Ein schlanker, nativer Multimessenger für macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("Projekt") {
                HStack {
                    Button {
                        updater.checkManually()
                    } label: {
                        Label("Jetzt auf Updates prüfen", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(updater.checking)
                    if updater.checking {
                        ProgressView().controlSize(.small)
                    } else if !updater.statusText.isEmpty {
                        Text(updater.statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Link(destination: URL(string: Self.repoURL)!) {
                    Label("Auf GitHub ansehen", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.repoURL, forType: .string)
                    importMessage = "GitHub-Link kopiert."
                } label: {
                    Label("Repository-Link kopieren", systemImage: "doc.on.doc")
                }
                Link(destination: URL(string: Self.repoURL + "/issues/new")!) {
                    Label("Fehler melden / Idee vorschlagen", systemImage: "ladybug")
                }
            }

            Section {
                Label {
                    Text("„Vibecoded“ mit Claude – als Hobby-/Bastelprojekt entstanden, kein kommerzielles Produkt.")
                } icon: { Image(systemName: "sparkles") }
                Label {
                    Text("Nicht von Apple signiert/notarisiert. Beim ersten Start ggf. Rechtsklick → Öffnen (Gatekeeper).")
                } icon: { Image(systemName: "lock.open") }
                Label {
                    Text("Nutzung auf eigene Verantwortung – keine Garantie, keine Haftung.")
                } icon: { Image(systemName: "exclamationmark.triangle") }
            } header: {
                Text("Gut zu wissen")
            } footer: {
                Text("Details, Installation und bekannte Einschränkungen stehen in der README auf GitHub.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Helfer

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0 }
        )
    }
}
