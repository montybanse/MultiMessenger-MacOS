import Foundation

/// In jede Seite injizierter JavaScript-Code:
///  - leitet Web-Benachrichtigungen an die native macOS-Mitteilungszentrale weiter
///  - liest die Ungelesen-Anzahl aus dem Tab-Titel (z.B. "(3) WhatsApp")
enum Bridge {
    static let userScript = """
    (function() {
        try {
            const post = function(name, payload) {
                try { window.webkit.messageHandlers[name].postMessage(payload); } catch (e) {}
            };

            // --- Web-Notification-API auf native Benachrichtigungen umleiten ---
            function MMNotification(title, options) {
                options = options || {};
                // Absolute URL des Benachrichtigungs-Icons (z.B. Kontaktbild) bilden.
                var icon = options.icon || options.image || '';
                try { if (icon) icon = new URL(icon, document.baseURI).href; } catch (e) {}
                post('notify', {
                    title: String(title || ''),
                    body:  String(options.body || ''),
                    tag:   String(options.tag || ''),
                    icon:  String(icon || '')
                });
                this.title = title;
                this.onclick = null;
                this.onclose = null;
                this.onerror = null;
                this.onshow = null;
                this.close = function() {};
            }
            MMNotification.permission = 'granted';
            MMNotification.requestPermission = function(cb) {
                if (typeof cb === 'function') cb('granted');
                return Promise.resolve('granted');
            };
            try {
                Object.defineProperty(window, 'Notification', {
                    value: MMNotification, writable: true, configurable: true
                });
            } catch (e) { window.Notification = MMNotification; }

            // --- Ungelesen-Anzahl aus dem Titel lesen ---
            let lastCount = -1;
            function parseCount() {
                const t = document.title || '';
                let count = 0;
                const paren = t.match(/\\((\\d+)\\)/);
                const lead  = t.match(/^\\s*(\\d+)\\s/);
                if (paren) {
                    count = parseInt(paren[1], 10);
                } else if (lead) {
                    count = parseInt(lead[1], 10);
                } else if (/[•·🔴🔵]/.test(t)) {
                    count = 1; // Marker ohne Zahl -> "es gibt Ungelesenes"
                }
                if (count !== lastCount) {
                    lastCount = count;
                    post('badge', { count: count });
                }
            }

            function startObserving() {
                const titleEl = document.querySelector('title');
                if (titleEl && window.MutationObserver) {
                    new MutationObserver(parseCount).observe(titleEl, { childList: true });
                }
                parseCount();
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', startObserving);
            } else {
                startObserving();
            }
            setInterval(parseCount, 4000);
        } catch (e) {}
    })();
    """

    /// Behebt zwei Probleme des eingebauten Mac-Mikrofons in WebRTC-Anrufen:
    ///  1) Stummbleiben durch den macOS-Voice-Processing-Konflikt
    ///     → echoCancellation aus (umgeht die problematische Audio-Unit).
    ///  2) Zu leises Signal → eigene Pegel-Anhebung per WebAudio-GainNode
    ///     (deterministisch, statt der unzuverlässigen Browser-AGC).
    static func micCompatScript(gain: Double) -> String {
        return """
        (function() {
            try {
                if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return;
                var GAIN = \(gain);
                var orig = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
                navigator.mediaDevices.getUserMedia = function(constraints) {
                    try {
                        if (constraints && constraints.audio) {
                            var a = (typeof constraints.audio === 'object') ? constraints.audio : {};
                            // Nur die Echounterdrückung abschalten – sie verursacht das
                            // Stummbleiben des internen Mikros. Rauschunterdrückung und
                            // automatische Pegelregelung BLEIBEN an (sorgen für Lautstärke).
                            a.echoCancellation = false;
                            if (a.noiseSuppression === undefined) a.noiseSuppression = true;
                            if (a.autoGainControl === undefined) a.autoGainControl = true;
                            constraints.audio = a;
                        }
                    } catch (e) {}

                    return orig(constraints).then(function(stream) {
                        try {
                            if (!constraints || !constraints.audio || GAIN === 1) return stream;
                            var AC = window.AudioContext || window.webkitAudioContext;
                            if (!AC) return stream;
                            var ctx = new AC();
                            // AudioContext bei Autoplay-Sperre aufwecken – sonst fließt
                            // kein Ton und die Verstärkung bliebe wirkungslos.
                            if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} }
                            var src = ctx.createMediaStreamSource(stream);
                            var g = ctx.createGain();
                            g.gain.value = GAIN;
                            var dest = ctx.createMediaStreamDestination();
                            src.connect(g); g.connect(dest);

                            // Verstärkte Audiospur in den Original-Stream einsetzen,
                            // Videospuren unverändert lassen.
                            var out = dest.stream.getAudioTracks()[0];
                            stream.getAudioTracks().forEach(function(t) {
                                stream.removeTrack(t);
                                // Original-Track stoppen wir NICHT (sonst endet die Quelle).
                            });
                            stream.addTrack(out);
                            return stream;
                        } catch (e) { return stream; }
                    });
                };
            } catch (e) {}
        })();
        """
    }

    /// Erzeugt das nutzerdefinierte CSS/JS-Snippet eines Dienstes.
    static func customInjection(css: String, js: String) -> String? {
        let trimmedCSS = css.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJS = js.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCSS.isEmpty && trimmedJS.isEmpty { return nil }

        var parts: [String] = ["(function(){ try {"]
        if !trimmedCSS.isEmpty {
            let escaped = trimmedCSS
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            parts.append("""
                var s = document.createElement('style');
                s.textContent = `\(escaped)`;
                (document.head || document.documentElement).appendChild(s);
            """)
        }
        if !trimmedJS.isEmpty {
            parts.append(trimmedJS)
        }
        parts.append("} catch(e) {} })();")
        return parts.joined(separator: "\n")
    }
}
