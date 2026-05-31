import Foundation

// MARK: - Schlaf-Strategie pro Dienst

enum SleepPolicy: String, Codable, CaseIterable, Identifiable {
    case sleepWhenInactive   // Standard: nach Inaktivität entladen -> spart RAM
    case alwaysAwake         // immer geladen (z.B. WhatsApp), liefert sofort Benachrichtigungen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleepWhenInactive: return "Schlafen, wenn inaktiv"
        case .alwaysAwake:       return "Immer wach halten"
        }
    }
}

// MARK: - Workspace (Gruppierung von Diensten)

struct Workspace: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "square.grid.2x2"
}

// MARK: - Dienst

struct Service: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var urlString: String
    var workspaceID: UUID? = nil

    var sleepPolicy: SleepPolicy = .sleepWhenInactive
    var muted: Bool = false
    var zoom: Double = 1.0

    var customCSS: String = ""
    var customJS: String = ""

    /// SF-Symbol als Fallback-Icon
    var iconSymbol: String = "globe"
    /// Optionales, vom Nutzer hochgeladenes Icon (PNG/JPEG-Daten)
    var iconData: Data? = nil
    /// Wenn true: Favicon der Seite verwenden (falls verfügbar)
    var useFavicon: Bool = true
    /// Zwischengespeichertes Favicon
    var faviconData: Data? = nil

    /// Stabile ID für die isolierte WKWebsiteDataStore (eigene Session/Cookies)
    var dataStoreID: UUID = UUID()

    /// Aus welcher Vorlage erstellt (optional)
    var templateID: String? = nil

    /// Eigener User-Agent für genau diesen Dienst (leer = globale/Standard-Kennung).
    /// Manche Dienste (z.B. Slack, MS Teams) verlangen eine Chrome-Kennung.
    var userAgent: String = ""

    var host: String? {
        URL(string: urlString)?.host
    }
}

/// Vordefinierte User-Agent-Kennungen.
enum UserAgentPreset {
    static let safari =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.3 Safari/605.1.15"
    // Hinweis: Slack/Teams/BBB prüfen die Versionsnummer aus der Kennung und
    // verlangen die „aktuelle" Browserversion. Bei erneuten „veralteter Browser"-
    // Meldungen diese Zahl auf eine aktuelle Chrome-Version anheben.
    static let chrome =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
}

// MARK: - App-Einstellungen

enum TabBarPosition: String, Codable, CaseIterable, Identifiable {
    case left, right, top, bottom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .left:   return "Links"
        case .right:  return "Rechts"
        case .top:    return "Oben"
        case .bottom: return "Unten"
        }
    }
    var isVertical: Bool { self == .left || self == .right }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System folgen"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }
}

struct AppSettings: Codable {
    var tabBarPosition: TabBarPosition = .left
    var appearance: AppearanceMode = .system

    var startAtLogin: Bool = false
    var keepRunningInBackground: Bool = true

    var dndEnabled: Bool = false          // global "Nicht stören"
    var lockEnabled: Bool = false         // Touch-ID / Passwort-Sperre
    var requireBiometricForLogin: Bool = true  // Touch ID vor dem Ausfüllen

    var globalHotkeyEnabled: Bool = true  // Cmd+Shift+M -> App nach vorne

    /// Zeit in Sekunden, bis ein inaktiver Dienst schlafen gelegt wird
    var sleepDelaySeconds: Double = 300

    /// Optionaler eigener User-Agent (leer = Standard-Safari-UA)
    var customUserAgent: String = ""

    /// Web-Inspektor aktivieren (Rechtsklick → „Element-Informationen“ / Konsole)
    /// – zur Fehlersuche bei Webdiensten.
    var webInspectorEnabled: Bool = false

    /// Mikrofon-Kompatibilitätsmodus: deaktiviert Echo-/Rauschunterdrückung im
    /// Browser, damit das eingebaute Mac-Mikrofon in WebRTC-Anrufen (BBB, Meet …)
    /// funktioniert. Workaround für den macOS-Voice-Processing-Konflikt.
    var micCompatMode: Bool = false

    /// Lautstärke-Anhebung des Mikrofons im Kompatibilitätsmodus (1.0 = neutral).
    var micGain: Double = 2.5
}
