import Foundation
import UserNotifications
import AppKit

/// Brücke zur nativen macOS-Mitteilungszentrale.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Wird aufgerufen, wenn der Nutzer auf eine Benachrichtigung klickt.
    var onActivateService: ((UUID) -> Void)?

    private override init() { super.init() }

    // Aktions-IDs für Download-Benachrichtigungen.
    private static let downloadCategory = "DOWNLOAD_DONE"
    private static let actionOpenFile = "OPEN_FILE"
    private static let actionReveal = "REVEAL_FILE"

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Kategorie für Downloads mit Aktions-Buttons registrieren.
        let open = UNNotificationAction(identifier: Self.actionOpenFile,
                                        title: "Öffnen", options: [.foreground])
        let reveal = UNNotificationAction(identifier: Self.actionReveal,
                                          title: "Im Finder zeigen", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.downloadCategory,
                                              actions: [open, reveal],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Benachrichtigung nach abgeschlossenem Download – mit Öffnen / Im Finder zeigen.
    func postDownloadComplete(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Download abgeschlossen"
        content.body = fileURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = Self.downloadCategory
        content.userInfo = ["downloadPath": fileURL.path]

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func post(serviceID: UUID, serviceName: String, title: String, body: String,
              iconURLString: String = "", fallbackIcon: Data? = nil,
              showBanner: Bool = true, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.subtitle = (title == serviceName) ? "" : serviceName
        content.sound = playSound ? .default : nil
        content.userInfo = [
            "serviceID": serviceID.uuidString,
            "showBanner": showBanner,
            "playSound": playSound
        ]

        // Icon laden (Kontaktbild aus der Web-Benachrichtigung) und als Anhang
        // anzeigen; sonst auf das Dienst-Icon zurückfallen.
        Task {
            if let attachment = await Self.makeAttachment(iconURLString: iconURLString,
                                                          fallbackIcon: fallbackIcon) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Erzeugt einen Bild-Anhang aus einer URL bzw. den Fallback-Icon-Daten.
    private static func makeAttachment(iconURLString: String,
                                       fallbackIcon: Data?) async -> UNNotificationAttachment? {
        var imageData: Data? = nil
        if !iconURLString.isEmpty,
           let url = URL(string: iconURLString),
           url.scheme == "http" || url.scheme == "https" {
            imageData = try? await URLSession.shared.data(from: url).0
        }
        if imageData == nil {
            imageData = fallbackIcon
        }
        guard let data = imageData, NSImage(data: data) != nil else {
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mm-notif", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try data.write(to: file)
            return try UNNotificationAttachment(identifier: "icon", url: file, options: nil)
        } catch {
            return nil
        }
    }

    // Benachrichtigungen auch anzeigen, wenn die App im Vordergrund ist –
    // unter Beachtung der Dienst-Regel (Banner/Ton einzeln steuerbar).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let showBanner = (info["showBanner"] as? Bool) ?? true
        let playSound = (info["playSound"] as? Bool) ?? true
        var options: UNNotificationPresentationOptions = [.list]
        if showBanner { options.insert(.banner) }
        if playSound { options.insert(.sound) }
        completionHandler(options)
    }

    // Klick auf Benachrichtigung -> Dienst öffnen bzw. Download-Aktion ausführen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo

        // Download-Benachrichtigung?
        if let path = info["downloadPath"] as? String {
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                switch response.actionIdentifier {
                case Self.actionOpenFile:
                    // Datei direkt öffnen.
                    NSWorkspace.shared.open(url)
                default:
                    // Standard-Klick oder „Im Finder zeigen" -> im Finder markieren.
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            completionHandler()
            return
        }

        // Sonst: Nachricht eines Dienstes -> Dienst öffnen.
        if let idString = info["serviceID"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onActivateService?(id)
            }
        }
        completionHandler()
    }
}
