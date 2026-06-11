import LocalAuthentication
import Foundation

/// Gemeinsame Touch-ID-/Passwort-Abfrage (Fallback aufs Account-Passwort,
/// wenn keine Biometrie verfügbar ist). Ergebnis kommt auf dem Main Thread.
enum BiometricAuth {
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        ctx.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
