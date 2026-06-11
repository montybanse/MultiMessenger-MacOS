import WebKit
import Combine

/// Mikrofon-Test durch die Web-Ansicht (Einstellungen → Erweitert).
/// Erstellt eine unsichtbare WKWebView, fordert getUserMedia GENAU SO an,
/// wie es BBB & Co. tun (inkl. aktivem Kompatibilitätsmodus-Skript) und
/// misst den Pegel der Spur, die die Seite tatsächlich bekommt.
/// Gegenstück zum nativen Test: Liefert der native Test Pegel, dieser hier
/// aber nicht, liegt das Problem in WebKit bzw. an der Skript-Kette.
@MainActor
final class WebMicTester: NSObject, ObservableObject {
    @Published var level: Double = 0
    @Published var peak: Double = 0
    @Published var trackLabel: String = ""
    @Published var errorText: String = ""
    @Published var running = false

    private var webView: WKWebView?

    func start(micCompatMode: Bool, micGain: Double) {
        stop()
        errorText = ""
        trackLabel = ""
        peak = 0

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        // Dieselbe Injektion wie bei echten Diensten, damit der Test die
        // identische Audio-Kette durchläuft.
        if micCompatMode {
            controller.addUserScript(WKUserScript(
                source: Bridge.micCompatScript(gain: micGain),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        controller.add(self, name: "micTest")
        config.userContentController = controller

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.uiDelegate = self
        webView = wv
        // baseURL mit https -> sicherer Kontext, sonst verweigert WebKit getUserMedia.
        wv.loadHTMLString(Self.html, baseURL: URL(string: "https://mic-test.local")!)
        running = true
    }

    func stop() {
        webView?.evaluateJavaScript("window.__mmStopTest && window.__mmStopTest();")
        webView?.stopLoading()
        webView = nil
        running = false
        level = 0
    }

    /// Testseite: fordert Audio mit Echounterdrückung an (wie BBB) und meldet
    /// Label + RMS-Pegel der erhaltenen Spur zurück.
    private static let html = """
    <!doctype html><html><body><script>
    (async function() {
        function post(m) { try { webkit.messageHandlers.micTest.postMessage(m); } catch (e) {} }
        try {
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                post({ type: 'error', message: 'getUserMedia nicht verfügbar' });
                return;
            }
            const stream = await navigator.mediaDevices.getUserMedia({
                audio: { echoCancellation: true, noiseSuppression: true }
            });
            const track = stream.getAudioTracks()[0];
            post({ type: 'label', label: track ? (track.label || '(ohne Label)') : '(keine Audiospur!)' });

            const AC = window.AudioContext || window.webkitAudioContext;
            const ctx = new AC();
            if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} }
            const src = ctx.createMediaStreamSource(stream);
            const an = ctx.createAnalyser();
            an.fftSize = 1024;
            src.connect(an);
            const buf = new Float32Array(an.fftSize);
            const timer = setInterval(function() {
                an.getFloatTimeDomainData(buf);
                let s = 0;
                for (let i = 0; i < buf.length; i++) s += buf[i] * buf[i];
                post({ type: 'level', rms: Math.sqrt(s / buf.length) });
            }, 100);

            window.__mmStopTest = function() {
                clearInterval(timer);
                try { stream.getTracks().forEach(function(t) { t.stop(); }); } catch (e) {}
                try { ctx.close(); } catch (e) {}
            };
        } catch (e) {
            post({ type: 'error', message: String((e && e.message) || e) });
        }
    })();
    </script></body></html>
    """
}

extension WebMicTester: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        switch dict["type"] as? String {
        case "label":
            trackLabel = dict["label"] as? String ?? ""
        case "level":
            let rms = dict["rms"] as? Double ?? 0
            // Gleiche dB-Skala wie der native Test (-50 dB -> 0, 0 dB -> 1).
            let db = 20 * log10(max(rms, 0.00001))
            let norm = min(max((db + 50) / 50, 0), 1)
            level = level * 0.6 + norm * 0.4
            if norm > peak { peak = norm }
        case "error":
            errorText = dict["message"] as? String ?? "Unbekannter Fehler"
            running = false
        default:
            break
        }
    }
}

extension WebMicTester: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}
