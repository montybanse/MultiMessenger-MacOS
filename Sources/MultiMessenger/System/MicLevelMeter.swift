import AVFoundation
import Combine

/// Nativer Mikrofon-Pegeltest (Einstellungen → Erweitert).
/// Misst den Eingangspegel direkt über CoreAudio/AVAudioEngine – also OHNE
/// WebKit. Damit lässt sich eingrenzen, ob ein stummes Mikro in BBB & Co.
/// am System (Pegel hier schon niedrig) oder an WebKit liegt (Pegel hier ok).
@MainActor
final class MicLevelMeter: ObservableObject {
    /// Geglätteter Pegel 0…1 für die Anzeige.
    @Published var level: Double = 0
    /// Spitzenwert seit Start (zeigt, ob überhaupt je Signal ankam).
    @Published var peak: Double = 0
    @Published var running = false
    @Published var deviceName: String = ""
    @Published var errorText: String = ""

    private var engine: AVAudioEngine?

    func start() {
        guard !running else { return }
        errorText = ""
        peak = 0

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.errorText = "Kein Mikrofonzugriff erlaubt (Systemeinstellungen → Datenschutz)."
                    return
                }
                self.startEngine()
            }
        }
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorText = "Kein Eingabegerät gefunden."
            return
        }

        deviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Standard-Eingang"

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(n))
            // RMS (≈0…1) in eine gut ablesbare dB-Skala umrechnen:
            // -50 dB -> 0, 0 dB -> 1. Sprache am internen Mikro liegt
            // typischerweise bei -35…-15 dB.
            let db = 20 * log10(max(rms, 0.00001))
            let norm = Double(min(max((db + 50) / 50, 0), 1))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = self.level * 0.6 + norm * 0.4   // glätten
                if norm > self.peak { self.peak = norm }
            }
        }

        do {
            try engine.start()
            self.engine = engine
            running = true
        } catch {
            errorText = "Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        running = false
        level = 0
    }
}
