# MultiMessenger für macOS

Ein schlanker, **nativer** Multimessenger für macOS. Bindet beliebig viele
Messenger und Webseiten (WhatsApp, Slack, Mattermost, Telegram, LinkedIn,
BigBlueButton, …) in **einer** App zusammen – jeweils mit eigener, isolierter
Sitzung.

Gebaut mit **Swift + SwiftUI + WKWebView** (die System-WebKit-Engine, dieselbe
wie Safari). Dadurch deutlich **ressourcenschonender** als Electron-basierte
Alternativen wie Franz oder Rambox, und es fügt sich nativ in macOS ein.

---

## ⚠️ Bitte zuerst lesen

- **„Vibecoded“.** Dieses Projekt ist im Dialog mit einem KI-Assistenten
  (Claude) als **Hobby-/Bastelprojekt** entstanden. Es ist **kein** kommerzielles
  oder professionell auditiertes Produkt.
- **Keine Apple-Signatur / keine Notarisierung.** Es gibt keinen
  Apple-Developer-Account hinter dem Projekt. Die App ist nur lokal
  (selbst-)signiert. → Beim ersten Start greift **Gatekeeper** (siehe unten).
- **Nutzung auf eigene Verantwortung.** Keine Garantie, keine Haftung. Du
  vertraust deine Messenger-Logins einer selbstgebauten App an – das solltest du
  bewusst entscheiden. Der Code liegt offen hier im Repo.
- **Bekannte kosmetische Einschränkung:** In macOS-Benachrichtigungen bleibt das
  kleine **App-Logo links leer** (das Kontaktbild rechts wird angezeigt). Ursache
  ist die fehlende Apple-Notarisierung; ohne Developer-Account nicht lösbar. Die
  Benachrichtigungen funktionieren ansonsten vollständig.

---

## Installation (fertige App)

1. Aktuelle **`MultiMessenger.dmg`** herunterladen
   (unter [Releases](https://github.com/montybanse/MultiMessenger-MacOS/releases)
   oder aus dem Ordner [`dist/`](dist/)).
2. Die `.dmg` öffnen und **MultiMessenger** auf den **Applications**-Ordner ziehen.
3. **Erster Start (wichtig wegen Gatekeeper):**
   - **Rechtsklick** (bzw. Ctrl-Klick) auf `MultiMessenger.app` → **Öffnen**.
   - Im Dialog nochmals auf **Öffnen** klicken.
   - Falls macOS den Start trotzdem blockiert:
     **Systemeinstellungen → Datenschutz & Sicherheit** → unten bei der Meldung
     zu MultiMessenger auf **„Trotzdem öffnen“** klicken.
   - Das ist nur **einmalig** nötig. Danach startet die App per Doppelklick.

> Warum diese Hürde? macOS lässt unsignierte/nicht-notarisierte Apps nicht
> einfach per Doppelklick zu. Da das Projekt keinen Apple-Developer-Account hat,
> ist der Rechtsklick-→-Öffnen-Weg der vorgesehene Weg.

---

## Selbst bauen (aus dem Quellcode)

**Voraussetzungen:** macOS 14+, Apple Silicon, Xcode **Command Line Tools**
(`xcode-select --install`). Ein volles Xcode ist **nicht** nötig.

```bash
# 1. Kompilieren + App-Bundle erzeugen (inkl. Icon & Share-Extension)
./build-app.sh

# 2. Starten
open dist/MultiMessenger.app

# optional: verteilbare .dmg erzeugen
./make-dmg.sh
```

Schnell für die Entwicklung:

```bash
swift build            # nur kompilieren
swift run MultiMessenger
```

### Optional: stabile lokale Signatur

Ohne stabile Signatur ändert sich bei jedem Build der Signatur-Fingerabdruck –
dann fragt der Schlüsselbund wiederholt nach Zugriff. Einmalig ein lokales,
selbst-signiertes Zertifikat anlegen (fragt **einmal** nach deinem
Schlüsselbund-Passwort):

```bash
./setup-cert.sh        # erstellt Zertifikat "MultiMessenger Local"
./build-app.sh         # signiert ab jetzt automatisch damit
```

> Dieses Zertifikat gilt nur auf **deinem** Mac. Für eine Weitergabe ohne
> Gatekeeper-Warnung bräuchte es einen Apple-Developer-Account (Notarisierung).

---

## Funktionen

- **Beliebig viele Dienste** über Vorlagen-Katalog oder freie URL, mit eigenem Icon
- **Offizielle Logos** werden live geladen (wie ein Browser; nichts wird mitgeliefert)
- **Tableiste** links / rechts / oben / unten umschaltbar
- **Workspaces** zum Gruppieren von Diensten
- **Isolierte Sitzung pro Dienst** → derselbe Dienst mehrfach mit verschiedenen Konten
- **Schlafmodus pro Dienst** (entlädt inaktive Dienste → spart RAM) inkl.
  „Jetzt schlafen legen“ und Pause-Symbol auf schlafenden Diensten
- **Native Benachrichtigungen** + Ungelesen-Badge pro Dienst +
  Menüleisten-Symbol mit Gesamtzahl + „Nicht stören“ + Stummschalten pro Dienst
- **Benachrichtigungsregeln pro Dienst:** Banner+Ton / nur Banner / nur Ton / aus,
  optional mit **Stichwort-Filter** (nur melden, wenn z. B. „@name“ vorkommt)
- **Menüleisten-Popover:** Links-Klick aufs Menüleisten-Symbol zeigt alle Dienste
  mit Ungelesen-Zählern + DND-Schalter, Klick springt zum Dienst (Rechts-Klick = Menü)
- **Einzelne Dienste mit Touch ID schützen** (z. B. privater Account) – zusätzlich
  zur App-Sperre
- **Akzentfarbe pro Workspace** – die Oberfläche färbt sich passend zum aktiven
  Workspace (Arbeit/Privat sofort erkennbar)
- **„Immer wach“-Dienste werden beim Start vorgeladen** (Benachrichtigungen ab Start)
- **Kontaktbild** in Benachrichtigungen (sofern der Dienst es mitliefert)
- **Browser-Kennung pro Dienst** (Safari/Chrome/eigene) – nötig für Slack, MS
  Teams und den virtuellen Hintergrund in BigBlueButton
- **Mikrofon-Kompatibilitätsmodus** mit Pegel-Regler (für interne Mac-Mikros in
  WebRTC-Anrufen)
- **Login-Helfer** (Schlüsselbund, optional Touch ID) – Ausfüllen per ⌘⇧L
- **Touch-ID-/Passwort-Sperre** der App (optional)
- **Autostart** beim Anmelden + Hintergrundbetrieb
- **Tastatur:** ⌘1…9 Dienst wechseln · ⌘K Schnell-Umschalter · ⌘R neu laden ·
  ⌘⇧M global hervorholen · ⌘⇧L Login ausfüllen
- **Teilen:** Links per Teilen-Menü / Dienste-Menü / URL-Schema `mmsg://` an einen
  Dienst übergeben (praktisch z. B. für BBB-Links aus dem Kalender)
- **Externe Links** im Standardbrowser, **Downloads** in den Download-Ordner
- **Pro Dienst:** Zoomstufe, eigenes CSS/JavaScript
- **Backup:** Konfiguration als `.json` exportieren/importieren
- Moderne SwiftUI-Oberfläche mit System-Materials (Hell/Dunkel, System-Akzent)

---

## Bekannte Einschränkungen

- **Notification-App-Logo links leer** – siehe oben (Notarisierung).
- **WhatsApp-Anrufe** funktionieren nicht – WhatsApp Web unterstützt Sprach-/
  Videoanrufe in **keinem** Browser, nur in den nativen Apps.
- **Mikrofon-Lautstärke** interner Mac-Mikrofone kann in manchen Diensten leiser
  sein als mit externem Mikro/AirPods (System-/WebRTC-bedingt; der
  Kompatibilitätsmodus mildert es).
- **Manche Dienste** verlangen die Chrome-Kennung (Slack, Teams, BBB-Hintergrund).
  Umschaltbar pro Dienst unter *Bearbeiten → Kompatibilität*.
- Weitergabe an andere Macs: dort erneut **Rechtsklick → Öffnen** (nicht notarisiert).

---

## Datenablage

| Was | Ort |
|-----|-----|
| Konfiguration (Dienste, Workspaces, Einstellungen) | `~/Library/Application Support/MultiMessenger/store.json` |
| Logins / Cookies pro Dienst | isolierte WebKit-Datastores (vom System verwaltet) |
| Geladene Logos (Cache) | `~/Library/Caches/MultiMessenger/icons` |

Die Daten liegen **außerhalb** des App-Bundles und bleiben bei Updates erhalten.

---

## Technik (kurz)

- **Sprache/UI:** Swift, SwiftUI, AppKit-Brücken wo nötig
- **Web:** ein `WKWebView` pro Dienst, eigener `WKWebsiteDataStore` je Dienst
- **Build:** Swift Package Manager + Shell-Skripte (`build-app.sh`, `make-dmg.sh`,
  `make-icon.sh`, `setup-cert.sh`) – **kein** Xcode-Projekt
- **Benachrichtigungen:** Web-`Notification`-API wird per JS-Bridge an die native
  `UNUserNotificationCenter`-API weitergereicht

---

## Lizenz

Siehe [`LICENSE`](LICENSE) (MIT). Nutzung auf eigene Verantwortung.

---

## Mitwirken

Issues und Ideen sind willkommen:
[Issue eröffnen](https://github.com/montybanse/MultiMessenger-MacOS/issues/new).
Da es ein Freizeitprojekt ist, kann es bei Antworten/Fixes aber dauern. 🙂
