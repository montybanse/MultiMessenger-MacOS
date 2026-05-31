import SwiftUI
import LocalAuthentication

/// Sperrbildschirm mit Touch ID / Passwort.
struct LockView: View {
    @EnvironmentObject var app: AppState
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(.tint)
                Text("MultiMessenger ist gesperrt")
                    .font(.title2.weight(.semibold))
                if failed {
                    Text("Authentifizierung fehlgeschlagen.")
                        .foregroundStyle(.red)
                }
                Button {
                    authenticate()
                } label: {
                    Label("Entsperren", systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Passwort verwenden"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: "MultiMessenger entsperren") { success, _ in
            DispatchQueue.main.async {
                if success {
                    app.isLocked = false
                    failed = false
                } else {
                    failed = true
                }
            }
        }
    }
}
