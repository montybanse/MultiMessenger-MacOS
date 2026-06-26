import Foundation
import SwiftUI

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
    /// Optionale Akzentfarbe des Workspace (Schlüssel aus AccentPalette).
    /// nil = System-Akzentfarbe.
    var accentKey: String? = nil

    /// Ruhezeiten: Benachrichtigungen aller Dienste dieses Workspace im
    /// Zeitfenster unterdrücken. Minuten seit Mitternacht; das Fenster darf
    /// über Mitternacht gehen (z.B. 18:00–08:00).
    var quietHoursEnabled: Bool = false
    var quietStartMinutes: Int = 18 * 60
    var quietEndMinutes: Int = 8 * 60

    init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", accentKey: String? = nil) {
        self.id = id; self.name = name; self.symbol = symbol; self.accentKey = accentKey
    }

    // Robustes Decoding (fehlende Felder -> Default), damit ältere store.json lädt.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbol    = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        accentKey = try c.decodeIfPresent(String.self, forKey: .accentKey)
        quietHoursEnabled = try c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? false
        quietStartMinutes = try c.decodeIfPresent(Int.self,  forKey: .quietStartMinutes) ?? 18 * 60
        quietEndMinutes   = try c.decodeIfPresent(Int.self,  forKey: .quietEndMinutes) ?? 8 * 60
    }

    /// Liegt `date` innerhalb der Ruhezeiten dieses Workspace?
    func isQuietNow(_ date: Date = Date()) -> Bool {
        guard quietHoursEnabled, quietStartMinutes != quietEndMinutes else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if quietStartMinutes < quietEndMinutes {
            return now >= quietStartMinutes && now < quietEndMinutes
        } else {
            // Fenster über Mitternacht (z.B. 18:00–08:00).
            return now >= quietStartMinutes || now < quietEndMinutes
        }
    }
}

// MARK: - Akzentfarben (pro Workspace wählbar)

enum AccentPalette {
    /// Reihenfolge stabil halten – die Schlüssel werden gespeichert.
    static let options: [(key: String, label: String, color: Color)] = [
        ("blue",   "Blau",    .blue),
        ("green",  "Grün",    .green),
        ("orange", "Orange",  .orange),
        ("pink",   "Pink",    .pink),
        ("purple", "Violett", .purple),
        ("teal",   "Türkis",  .teal),
        ("red",    "Rot",     .red),
        ("indigo", "Indigo",  .indigo),
        ("yellow", "Gelb",    .yellow),
        ("mint",   "Mint",    .mint),
    ]

    static func color(for key: String?) -> Color? {
        guard let key else { return nil }
        return options.first { $0.key == key }?.color
    }
}

// MARK: - Benachrichtigungs-Regel pro Dienst

enum NotificationStyle: String, Codable, CaseIterable, Identifiable {
    case bannerAndSound   // Banner + Ton (Standard)
    case bannerOnly       // nur Banner, kein Ton
    case soundOnly        // nur Ton, kein Banner
    case off              // keine Benachrichtigungen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .bannerAndSound: return "Banner + Ton"
        case .bannerOnly:     return "Nur Banner"
        case .soundOnly:      return "Nur Ton"
        case .off:            return "Aus"
        }
    }
    var showsBanner: Bool { self == .bannerAndSound || self == .bannerOnly }
    var playsSound: Bool  { self == .bannerAndSound || self == .soundOnly }
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

    /// Art der Benachrichtigung für diesen Dienst.
    var notificationStyle: NotificationStyle = .bannerAndSound
    /// Optionaler Stichwort-Filter: nur benachrichtigen, wenn Titel/Text eines
    /// dieser (kommagetrennten) Wörter enthält. Leer = alle Nachrichten.
    var notificationKeywords: String = ""

    /// Dienst hinter Touch ID / Passwort verbergen (zusätzlich zur App-Sperre).
    var locked: Bool = false

    /// Benachrichtigungen geschlummert bis zu diesem Zeitpunkt (nil = aktiv).
    var snoozedUntil: Date? = nil

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    var host: String? {
        URL(string: urlString)?.host
    }

    /// Prüft, ob eine Benachrichtigung mit diesem Titel/Text den Stichwortfilter passiert.
    func matchesNotificationFilter(title: String, body: String) -> Bool {
        let words = notificationKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if words.isEmpty { return true }
        let haystack = (title + " " + body).lowercased()
        return words.contains { haystack.contains($0) }
    }

    // Robustes Decoding: fehlende (neue) Felder fallen auf Default zurück,
    // damit ältere store.json-Dateien weiterhin geladen werden können.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,         forKey: .id) ?? UUID()
        name          = try c.decodeIfPresent(String.self,       forKey: .name) ?? ""
        urlString     = try c.decodeIfPresent(String.self,       forKey: .urlString) ?? ""
        workspaceID   = try c.decodeIfPresent(UUID.self,         forKey: .workspaceID)
        sleepPolicy   = try c.decodeIfPresent(SleepPolicy.self,  forKey: .sleepPolicy) ?? .sleepWhenInactive
        muted         = try c.decodeIfPresent(Bool.self,         forKey: .muted) ?? false
        zoom          = try c.decodeIfPresent(Double.self,       forKey: .zoom) ?? 1.0
        customCSS     = try c.decodeIfPresent(String.self,       forKey: .customCSS) ?? ""
        customJS      = try c.decodeIfPresent(String.self,       forKey: .customJS) ?? ""
        iconSymbol    = try c.decodeIfPresent(String.self,       forKey: .iconSymbol) ?? "globe"
        iconData      = try c.decodeIfPresent(Data.self,         forKey: .iconData)
        useFavicon    = try c.decodeIfPresent(Bool.self,         forKey: .useFavicon) ?? true
        faviconData   = try c.decodeIfPresent(Data.self,         forKey: .faviconData)
        dataStoreID   = try c.decodeIfPresent(UUID.self,         forKey: .dataStoreID) ?? UUID()
        templateID    = try c.decodeIfPresent(String.self,       forKey: .templateID)
        userAgent     = try c.decodeIfPresent(String.self,       forKey: .userAgent) ?? ""
        notificationStyle = try c.decodeIfPresent(NotificationStyle.self, forKey: .notificationStyle) ?? .bannerAndSound
        notificationKeywords = try c.decodeIfPresent(String.self, forKey: .notificationKeywords) ?? ""
        locked        = try c.decodeIfPresent(Bool.self,         forKey: .locked) ?? false
        snoozedUntil  = try c.decodeIfPresent(Date.self,         forKey: .snoozedUntil)
    }

    // Memberwise-Init bleibt erhalten (manuell, da init(from:) ihn sonst verdrängt).
    init(id: UUID = UUID(), name: String, urlString: String, workspaceID: UUID? = nil,
         sleepPolicy: SleepPolicy = .sleepWhenInactive, muted: Bool = false, zoom: Double = 1.0,
         customCSS: String = "", customJS: String = "", iconSymbol: String = "globe",
         iconData: Data? = nil, useFavicon: Bool = true, faviconData: Data? = nil,
         dataStoreID: UUID = UUID(), templateID: String? = nil, userAgent: String = "",
         notificationStyle: NotificationStyle = .bannerAndSound, notificationKeywords: String = "",
         locked: Bool = false) {
        self.id = id; self.name = name; self.urlString = urlString; self.workspaceID = workspaceID
        self.sleepPolicy = sleepPolicy; self.muted = muted; self.zoom = zoom
        self.customCSS = customCSS; self.customJS = customJS; self.iconSymbol = iconSymbol
        self.iconData = iconData; self.useFavicon = useFavicon; self.faviconData = faviconData
        self.dataStoreID = dataStoreID; self.templateID = templateID; self.userAgent = userAgent
        self.notificationStyle = notificationStyle; self.notificationKeywords = notificationKeywords
        self.locked = locked
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
        "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
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

    /// Mikrofon-Kompatibilitätsmodus: deaktiviert die Echounterdrückung im
    /// Browser, damit das eingebaute Mac-Mikrofon in WebRTC-Anrufen (BBB, Meet …)
    /// funktioniert (macOS-Voice-Processing-Konflikt). Standardmäßig AN, weil
    /// das interne Mikro sonst stumm bleibt – der seltene Nachteil (mögliches
    /// Echo bei Lautsprecher-Nutzung) ist das kleinere Übel. Abwahl bleibt
    /// gespeichert.
    var micCompatMode: Bool = true

    /// Lautstärke-Anhebung des Mikrofons im Kompatibilitätsmodus (1.0 = neutral).
    /// Standard 1.0: mehr Verstärkung ließ in BBB die Pegelanzeige dauerhaft
    /// ausschlagen; bei Bedarf per Slider (Erweitert) anheben.
    var micGain: Double = 1.0

    /// Werbe-/Tracker-Blocker (WKContentRuleList) für alle Dienste.
    var adBlockEnabled: Bool = false

    /// Beim Start (max. 1x pro Tag) auf neue GitHub-Releases prüfen.
    var updateCheckEnabled: Bool = true

    // Robustes Decoding: Eine neue Eigenschaft ohne decodeIfPresent würde jede
    // ältere store.json unlesbar machen (so entstand der Datenverlust v0.2.0).
    // Beim Hinzufügen von Feldern hier IMMER eine Zeile ergänzen.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabBarPosition  = try c.decodeIfPresent(TabBarPosition.self, forKey: .tabBarPosition) ?? .left
        appearance      = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        startAtLogin    = try c.decodeIfPresent(Bool.self,   forKey: .startAtLogin) ?? false
        keepRunningInBackground = try c.decodeIfPresent(Bool.self, forKey: .keepRunningInBackground) ?? true
        dndEnabled      = try c.decodeIfPresent(Bool.self,   forKey: .dndEnabled) ?? false
        lockEnabled     = try c.decodeIfPresent(Bool.self,   forKey: .lockEnabled) ?? false
        requireBiometricForLogin = try c.decodeIfPresent(Bool.self, forKey: .requireBiometricForLogin) ?? true
        globalHotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalHotkeyEnabled) ?? true
        sleepDelaySeconds = try c.decodeIfPresent(Double.self, forKey: .sleepDelaySeconds) ?? 300
        customUserAgent = try c.decodeIfPresent(String.self, forKey: .customUserAgent) ?? ""
        webInspectorEnabled = try c.decodeIfPresent(Bool.self, forKey: .webInspectorEnabled) ?? false
        micCompatMode   = try c.decodeIfPresent(Bool.self,   forKey: .micCompatMode) ?? true
        micGain         = try c.decodeIfPresent(Double.self, forKey: .micGain) ?? 1.0
        adBlockEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .adBlockEnabled) ?? false
        updateCheckEnabled = try c.decodeIfPresent(Bool.self, forKey: .updateCheckEnabled) ?? true
    }
}
