import WebKit

/// Werbe- und Tracker-Blocker auf Basis von WKContentRuleList.
/// Die Regeln werden von WebKit nativ (in C++) ausgewertet – das kostet
/// praktisch keine CPU, anders als JS-basierte Blocker.
///
/// Die Liste ist bewusst konservativ: nur reine Werbe-/Tracking-Netzwerke,
/// keine Domains, die Login- oder Chatfunktionen tragen könnten
/// (z.B. bleibt connect.facebook.net erreichbar, das „Login mit Facebook"
/// und Instagram-Ressourcen bedienen kann).
@MainActor
enum AdBlocker {
    /// Bei Änderungen an `blockedDomains` hochzählen, damit WebKit die
    /// gecachte kompilierte Liste verwirft und neu übersetzt.
    private static let identifier = "mm-adblock-v1"

    /// Kompilierte Regel-Liste; wird beim App-Start einmal befüllt.
    private(set) static var compiled: WKContentRuleList?

    private static let blockedDomains: [String] = [
        // Google-Werbung & -Tracking
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "adservice.google.de",
        // Allgemeine Ad-Netzwerke
        "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net",
        "casalemedia.com", "criteo.com", "criteo.net", "taboola.com",
        "outbrain.com", "smartadserver.com", "teads.tv", "adform.net",
        "yieldlab.net", "adition.com", "amazon-adsystem.com",
        // Mess-/Tracking-Dienste
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "moatads.com", "doubleverify.com",
        "adsafeprotected.com", "ioam.de", "branch.io",
    ]

    /// JSON im WKContentRuleList-Format aus der Domainliste erzeugen.
    private static var rulesJSON: String {
        let rules = blockedDomains.map { domain -> String in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\\\.")
            return """
            {"trigger":{"url-filter":"://([^/]+\\\\.)?\(escaped)[:/]","load-type":["third-party"]},"action":{"type":"block"}}
            """
        }
        // Facebook-Tracking-Pixel (pfadbasiert, blockiert NICHT facebook.com selbst).
        let fbPixel = """
        {"trigger":{"url-filter":"://www\\\\.facebook\\\\.com/tr[/?]","load-type":["third-party"]},"action":{"type":"block"}}
        """
        return "[" + (rules + [fbPixel]).joined(separator: ",") + "]"
    }

    /// Beim App-Start aufrufen: kompiliert die Liste (bzw. holt sie aus dem
    /// WebKit-Cache) und hält sie für neue WebViews bereit.
    static func prepare() {
        let json = rulesJSON
        let id = identifier
        let store = WKContentRuleListStore.default()
        store?.lookUpContentRuleList(forIdentifier: id) { list, _ in
            if let list {
                Task { @MainActor in compiled = list }
                return
            }
            store?.compileContentRuleList(forIdentifier: id,
                                          encodedContentRuleList: json) { list, error in
                if let error { NSLog("AdBlocker: Kompilierung fehlgeschlagen: \(error)") }
                Task { @MainActor in compiled = list }
            }
        }
    }
}
