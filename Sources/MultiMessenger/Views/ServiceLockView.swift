import SwiftUI
import LocalAuthentication

/// Sperrbildschirm für einen einzelnen, geschützten Dienst.
/// Verlangt Touch ID / Passwort, bevor der Dienst angezeigt wird.
struct ServiceLockView: View {
    @EnvironmentObject var app: AppState
    let service: Service
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(.tint)
            Text("„\(service.name)“ ist geschützt")
                .font(.title3.weight(.semibold))
            if failed {
                Text("Entsperrung fehlgeschlagen.")
                    .font(.callout).foregroundStyle(.red)
            }
            Button {
                authenticate()
            } label: {
                Label("Entsperren", systemImage: "touchid")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Passwort verwenden"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        context.evaluatePolicy(policy, localizedReason: "„\(service.name)“ entsperren") { success, _ in
            DispatchQueue.main.async {
                if success {
                    failed = false
                    app.markUnlocked(service.id)
                } else {
                    failed = true
                }
            }
        }
    }
}
