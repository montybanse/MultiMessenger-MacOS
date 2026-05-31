import SwiftUI
import AppKit

/// Lädt und cached die offiziellen Logos/Favicons der Dienste anhand ihrer
/// Domain. Quelle: DuckDuckGo- bzw. Google-Favicon-Dienst (wie ein Browser –
/// es werden keine Logos mit der App ausgeliefert). Ergebnis liegt im Cache
/// unter ~/Library/Caches/MultiMessenger/icons.
@MainActor
final class IconCache: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let dir: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MultiMessenger/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        dir = caches
    }

    func image(forURLString s: String) -> NSImage? {
        guard let host = Self.host(from: s) else { return nil }
        return image(forHost: host)
    }

    func image(forHost host: String) -> NSImage? {
        if let img = images[host] { return img }
        loadIfNeeded(host)
        return nil
    }

    private static func host(from s: String) -> String? {
        var str = s.trimmingCharacters(in: .whitespaces)
        guard !str.isEmpty else { return nil }
        if !str.contains("://") { str = "https://" + str }
        guard let host = URL(string: str)?.host, host.contains(".") else { return nil }
        return host
    }

    private func loadIfNeeded(_ host: String) {
        if inFlight.contains(host) || images[host] != nil { return }
        inFlight.insert(host)

        let file = dir.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_") + ".png")
        if let data = try? Data(contentsOf: file), let img = NSImage(data: data) {
            images[host] = img
            inFlight.remove(host)
            return
        }
        Task { await fetch(host: host, file: file) }
    }

    private func candidateURLs(_ host: String) -> [URL] {
        var hosts = [host]
        let parts = host.split(separator: ".")
        if parts.count > 2 { hosts.append(parts.suffix(2).joined(separator: ".")) }

        var urls: [URL] = []
        for h in hosts {
            if let u = URL(string: "https://icons.duckduckgo.com/ip3/\(h).ico") { urls.append(u) }
        }
        for h in hosts {
            if let u = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(h)") { urls.append(u) }
        }
        return urls
    }

    private func fetch(host: String, file: URL) async {
        for url in candidateURLs(host) {
            if let (data, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               data.count > 80, let img = NSImage(data: data), img.size.width >= 16 {
                try? data.write(to: file)
                images[host] = img
                inFlight.remove(host)
                return
            }
        }
        inFlight.remove(host)
    }
}
