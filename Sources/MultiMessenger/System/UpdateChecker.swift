import Foundation
import AppKit

/// Prüft die GitHub-Releases auf eine neuere Version.
/// Automatisch beim Start (max. 1x pro Tag) oder manuell aus dem Über-Tab.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Ergebnis des letzten manuellen Checks (für die Anzeige im Über-Tab).
    @Published var statusText: String = ""
    @Published var checking = false

    private static let apiURL =
        URL(string: "https://api.github.com/repos/montybanse/MultiMessenger-MacOS/releases/latest")!
    private static let lastCheckKey = "mm.update.lastCheck"
    private static let notifiedVersionKey = "mm.update.notifiedVersion"

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Beim App-Start aufrufen: prüft höchstens einmal pro Tag und meldet
    /// eine neue Version nur ein einziges Mal (per Benachrichtigung).
    func checkAtLaunch(enabled: Bool) {
        guard enabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }

        Task {
            guard let release = await fetchLatest() else { return }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            let latest = Self.normalize(release.tag_name)
            guard Self.isNewer(latest, than: currentVersion) else { return }
            // Jede Version nur einmal melden, sonst nervt es täglich.
            let already = UserDefaults.standard.string(forKey: Self.notifiedVersionKey)
            guard already != latest else { return }
            UserDefaults.standard.set(latest, forKey: Self.notifiedVersionKey)
            NotificationManager.shared.postUpdateAvailable(version: latest, url: release.html_url)
        }
    }

    /// Manueller Check aus den Einstellungen (Über-Tab).
    func checkManually() {
        checking = true
        statusText = ""
        Task {
            defer { checking = false }
            guard let release = await fetchLatest() else {
                statusText = "Prüfung fehlgeschlagen (keine Verbindung?)"
                return
            }
            let latest = Self.normalize(release.tag_name)
            if Self.isNewer(latest, than: currentVersion) {
                statusText = "Version \(latest) ist verfügbar!"
                if let url = URL(string: release.html_url) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                statusText = "Du bist auf dem neuesten Stand (\(currentVersion))."
            }
        }
    }

    private func fetchLatest() async -> Release? {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Release.self, from: data)
    }

    /// "v0.2.4" -> "0.2.4"
    private static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numerischer Vergleich der Versionskomponenten ("0.10.0" > "0.9.1").
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
