import AppKit
import WebKit

/// Hält eine WKWebView für genau einen Dienst, inklusive isolierter Session,
/// Benachrichtigungs-Brücke und Download-/Link-Handling.
@MainActor
final class ServiceWebView: NSObject {
    let serviceID: UUID
    let webView: WKWebView

    var onNotify: ((_ serviceID: UUID, _ title: String, _ body: String, _ iconURL: String) -> Void)?
    var onBadge:  ((_ serviceID: UUID, _ count: Int) -> Void)?

    init(service: Service, customUserAgent: String, micCompatMode: Bool, micGain: Double,
         webInspector: Bool) {
        self.serviceID = service.id

        let config = WKWebViewConfiguration()

        // Eigene, dauerhafte Session pro Dienst (Multi-Account-fähig).
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.dataStoreID)

        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Bridge.userScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        if micCompatMode {
            controller.addUserScript(WKUserScript(
                source: Bridge.micCompatScript(gain: micGain),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        if let custom = Bridge.customInjection(css: service.customCSS, js: service.customJS) {
            controller.addUserScript(WKUserScript(
                source: custom,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        config.userContentController = controller

        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        controller.add(WeakMessageHandler(self), name: "notify")
        controller.add(WeakMessageHandler(self), name: "badge")

        // Reihenfolge: Dienst-spezifischer UA > globaler UA > Safari-Standard.
        let perService = service.userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let global = customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        webView.customUserAgent = !perService.isEmpty ? perService
            : (!global.isEmpty ? global : UserAgentPreset.safari)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // transparenter Hintergrund -> Material durchscheinen
        if webInspector, #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        applyZoom(service.zoom)
        load(urlString: service.urlString)
    }

    func load(urlString: String) {
        guard let url = normalizedURL(urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    func reload() { webView.reload() }

    /// Füllt Benutzername/Passwort in das erkannte Login-Formular der Seite.
    func fillLogin(username: String, password: String) {
        let u = Self.jsString(username)
        let p = Self.jsString(password)
        let js = """
        (function(U, P) {
            try {
                function setVal(el, val) {
                    try {
                        var proto = window.HTMLInputElement.prototype;
                        var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
                        setter.call(el, val);
                    } catch (e) { el.value = val; }
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                }
                var visible = function(e) { return e && e.offsetParent !== null && !e.disabled; };
                var pwds = Array.prototype.slice.call(document.querySelectorAll('input[type=password]')).filter(visible);
                var pw = pwds[0] || null;
                var cands = Array.prototype.slice.call(
                    document.querySelectorAll('input[type=text],input[type=email],input[type=tel],input:not([type])')
                ).filter(visible);
                var user = null;
                if (pw) {
                    var before = cands.filter(function(e) {
                        return e.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING;
                    });
                    user = before.length ? before[before.length - 1] : (cands[0] || null);
                } else {
                    user = cands[0] || null;
                }
                if (user && U) setVal(user, U);
                if (pw && P) setVal(pw, P);
                return !!(user || pw);
            } catch (e) { return false; }
        })(\(u), \(p));
        """
        webView.evaluateJavaScript(js)
    }

    private static func jsString(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\"\""
    }

    func applyZoom(_ zoom: Double) {
        webView.pageZoom = CGFloat(zoom)
    }

    private func normalizedURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        return URL(string: "https://" + t)
    }
}

// MARK: - Nachrichten aus dem injizierten JS

extension ServiceWebView: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "notify":
            guard let dict = message.body as? [String: Any] else { return }
            let title = dict["title"] as? String ?? ""
            let body = dict["body"] as? String ?? ""
            let icon = dict["icon"] as? String ?? ""
            onNotify?(serviceID, title, body, icon)
        case "badge":
            guard let dict = message.body as? [String: Any],
                  let count = dict["count"] as? Int else { return }
            onBadge?(serviceID, count)
        default:
            break
        }
    }
}

// MARK: - Navigation / Links / Downloads

extension ServiceWebView: WKNavigationDelegate {
    // Externe Links (window.open / target=_blank) im Standardbrowser öffnen.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

extension ServiceWebView: WKUIDelegate {
    // window.open(...) -> im Standardbrowser öffnen, keine zweite WebView erzeugen.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    // Kamera/Mikrofon (BigBlueButton, Meet, Slack-Huddles ...) automatisch erlauben.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

extension ServiceWebView: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var dest = downloads.appendingPathComponent(suggestedFilename)
        var i = 1
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = downloads.appendingPathComponent(name)
            i += 1
        }
        completionHandler(dest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {}
    func downloadDidFinish(_ download: WKDownload) {}
}

/// Verhindert einen Retain-Cycle zwischen WKUserContentController und ServiceWebView.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: ServiceWebView?
    init(_ target: ServiceWebView) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
