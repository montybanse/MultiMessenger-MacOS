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

    /// Behebt drei Probleme des eingebauten Mac-Mikrofons in WebRTC-Anrufen:
    ///  1) Stummbleiben durch den macOS-Voice-Processing-Konflikt
    ///     → echoCancellation aus (umgeht die problematische Audio-Unit).
    ///  2) Zu leises Signal → Kompressor + Pegel-Anhebung per WebAudio
    ///     (deterministisch, statt der unzuverlässigen Browser-AGC).
    ///  3) Geräteerkennung (z.B. BBB-Echo-Test): die verarbeitete Spur hatte
    ///     weder label noch deviceId → Seiten hielten sie für „kein Mikrofon".
    ///     Jetzt wird die Identität des echten Mikros auf die Spur gespiegelt.
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
                            // Stummbleiben des internen Mikros.
                            a.echoCancellation = false;
                            if (a.noiseSuppression === undefined) a.noiseSuppression = true;
                            constraints.audio = a;
                        }
                    } catch (e) {}

                    return orig(constraints).then(function(stream) {
                        try {
                            if (!constraints || !constraints.audio || GAIN === 1) return stream;
                            var raw = stream.getAudioTracks()[0];
                            if (!raw) return stream;
                            var AC = window.AudioContext || window.webkitAudioContext;
                            if (!AC) return stream;

                            // WICHTIG: nur EINEN AudioContext wiederverwenden. Früher wurde
                            // pro getUserMedia ein neuer erzeugt und nie geschlossen – BBB
                            // ruft das mehrfach auf -> AudioContext-Leak -> Audio-Subsystem
                            // überlastet -> system­weiter Tastatur-Freeze. Jetzt geteilt.
                            if (!window.__mmAudioCtx) { window.__mmAudioCtx = new AC(); }
                            var ctx = window.__mmAudioCtx;
                            if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} }

                            // Pegelkette: Quelle -> Kompressor (fängt Spitzen ab, hebt
                            // leise Passagen an) -> Gain (Wunsch-Verstärkung) -> Ziel.
                            var src = ctx.createMediaStreamSource(new MediaStream([raw]));
                            var comp = ctx.createDynamicsCompressor();
                            comp.threshold.value = -24;
                            comp.knee.value = 30;
                            comp.ratio.value = 6;
                            comp.attack.value = 0.003;
                            comp.release.value = 0.25;
                            var g = ctx.createGain();
                            g.gain.value = GAIN;
                            var dest = ctx.createMediaStreamDestination();
                            src.connect(comp); comp.connect(g); g.connect(dest);

                            var out = dest.stream.getAudioTracks()[0];

                            // Identität des echten Mikrofons spiegeln, damit die Seite
                            // die Spur einem Gerät zuordnen kann (BBB prüft label/
                            // deviceId und zeigte sonst „kein Mikrofon erkannt").
                            try {
                                Object.defineProperty(out, 'label', {
                                    get: function() { return raw.label; }, configurable: true
                                });
                                out.getSettings = function() { return raw.getSettings(); };
                                out.getCapabilities = raw.getCapabilities
                                    ? function() { return raw.getCapabilities(); } : out.getCapabilities;
                                out.getConstraints = function() { return raw.getConstraints(); };
                                out.applyConstraints = function(c) { return raw.applyConstraints(c); };
                            } catch (e) {}

                            // Aufräumen in beide Richtungen: stoppt die Seite die Spur,
                            // muss auch das echte Mikro freigegeben werden (oranger
                            // Punkt aus) und die WebAudio-Knoten getrennt (kein Leak).
                            var done = false;
                            var cleanup = function() {
                                if (done) return; done = true;
                                try { src.disconnect(); } catch (e) {}
                                try { comp.disconnect(); } catch (e) {}
                                try { g.disconnect(); } catch (e) {}
                                try { raw.stop(); } catch (e) {}
                            };
                            var origStop = out.stop.bind(out);
                            out.stop = function() { cleanup(); origStop(); };
                            out.addEventListener('ended', cleanup);
                            raw.addEventListener('ended', cleanup);

                            stream.getAudioTracks().forEach(function(t) {
                                stream.removeTrack(t);
                                // Original-Track NICHT stoppen (sonst endet die Quelle).
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
