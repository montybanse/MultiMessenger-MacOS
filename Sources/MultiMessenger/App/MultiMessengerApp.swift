import SwiftUI

@main
struct MultiMessengerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("MultiMessenger", id: "main") {
            RootView()
                .environmentObject(delegate.app)
                .environmentObject(delegate.manager)
                .environmentObject(delegate.icons)
                .frame(minWidth: 700, minHeight: 480)
        }
        // Titelleiste bleibt vorhanden (für Doppelklick-Zoom), wird aber im
        // AppDelegate transparent gemacht -> nahtloser Look.
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Dienste") {
                Button("Schnell wechseln …") {
                    delegate.app.showQuickSwitcher.toggle()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Aktuellen Dienst neu laden") {
                    if let id = delegate.app.selectedServiceID {
                        NotificationCenter.default.post(name: .reloadService, object: id)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Anmeldedaten ausfüllen") {
                    if let id = delegate.app.selectedServiceID {
                        NotificationCenter.default.post(name: .fillLogin, object: id)
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { n in
                    Button("Dienst \(n)") {
                        delegate.app.selectIndex(n - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }
        }
    }
}

/// Wurzel-View: zeigt Inhalt und ggf. Sperrbildschirm, setzt das Erscheinungsbild.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: WebViewManager
    @EnvironmentObject var icons: IconCache

    var body: some View {
        ContentView()
            .environmentObject(app)
            .environmentObject(manager)
            .environmentObject(icons)
            .preferredColorScheme(app.colorScheme)
            .tint(app.currentAccent)   // Workspace-Akzentfarbe (nil = System)
            .overlay {
                if app.isLocked {
                    LockView().environmentObject(app)
                }
            }
    }
}
