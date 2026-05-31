import Foundation
import UserNotifications
import AppKit

/// Brücke zur nativen macOS-Mitteilungszentrale.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Wird aufgerufen, wenn der Nutzer auf eine Benachrichtigung klickt.
    var onActivateService: ((UUID) -> Void)?

    private override init() { super.init() }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(serviceID: UUID, serviceName: String, title: String, body: String,
              iconURLString: String = "", fallbackIcon: Data? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.subtitle = (title == serviceName) ? "" : serviceName
        content.sound = .default
        content.userInfo = ["serviceID": serviceID.uuidString]

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

    // Benachrichtigungen auch anzeigen, wenn die App im Vordergrund ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // Klick auf Benachrichtigung -> zugehörigen Dienst öffnen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let idString = response.notification.request.content.userInfo["serviceID"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onActivateService?(id)
            }
        }
        completionHandler()
    }
}
