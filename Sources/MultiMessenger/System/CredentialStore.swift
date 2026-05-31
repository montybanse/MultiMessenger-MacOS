import Foundation
import AppKit
import Security
import LocalAuthentication

struct LoginCredential: Codable {
    var username: String
    var password: String
}

/// Speichert Login-Daten pro Dienst sicher im macOS-Schlüsselbund.
/// `kSecAttrSynchronizable` aktiviert iCloud-Schlüsselbund-Sync (greift voll,
/// sobald die App regulär signiert ist; sonst lokal).
enum CredentialStore {
    private static let service = "eu.montybanse.MultiMessenger.login"

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }

    static func save(_ cred: LoginCredential, for id: UUID) {
        delete(id)
        guard let data = try? JSONEncoder().encode(cred) else { return }

        func attrs(sync: Bool) -> [String: Any] {
            var a = baseQuery(id)
            a[kSecValueData as String] = data
            a[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            if sync { a[kSecAttrSynchronizable as String] = kCFBooleanTrue! }
            return a
        }

        var status = SecItemAdd(attrs(sync: true) as CFDictionary, nil)
        // Falls iCloud-Sync mangels Entitlement scheitert: lokal speichern.
        if status == errSecMissingEntitlement || status == errSecParam {
            status = SecItemAdd(attrs(sync: false) as CFDictionary, nil)
        }
        if status != errSecSuccess {
            NSLog("CredentialStore.save Fehler: \(status)")
        }
    }

    static func load(_ id: UUID) -> LoginCredential? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LoginCredential.self, from: data)
    }

    static func has(_ id: UUID) -> Bool {
        var query = baseQuery(id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ id: UUID) {
        var query = baseQuery(id)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}

/// Füllt gespeicherte Anmeldedaten – optional erst nach Touch-ID-Bestätigung.
@MainActor
enum LoginFiller {
    static func fill(serviceID: UUID, requireBiometric: Bool, manager: WebViewManager) {
        guard CredentialStore.has(serviceID) else {
            NSSound.beep()
            return
        }
        let doFill = {
            guard let cred = CredentialStore.load(serviceID) else { return }
            manager.fill(serviceID: serviceID, username: cred.username, password: cred.password)
        }

        guard requireBiometric else { doFill(); return }

        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Passwort verwenden"
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        ctx.evaluatePolicy(policy, localizedReason: "Anmeldedaten ausfüllen") { ok, _ in
            if ok { DispatchQueue.main.async { doFill() } }
        }
    }
}
