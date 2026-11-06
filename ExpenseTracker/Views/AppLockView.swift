import SwiftUI
import LocalAuthentication

/// Full-screen cover shown when Face ID / passcode lock is on and the app was in the background.
struct AppLockView: View {
    let onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("AppLogo")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.emerald.opacity(0.35), radius: 16, y: 8)
            Text("Expenses is locked").font(.title3.weight(.bold))
            Text("Unlock with \(biometryName) to view your spending.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button(action: authenticate) {
                Label("Unlock", systemImage: biometrySymbol)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.emerald)
            .padding(.top, 6)
            if failed {
                Text("Couldn't verify — try again.").font(.footnote).foregroundStyle(Theme.danger)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .background(Theme.background)
        .onAppear(perform: authenticate)
    }

    private var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }
    private var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }
    private var biometrySymbol: String {
        switch biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open.fill"
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        // deviceOwnerAuthentication falls back to the device passcode.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onUnlock() // No passcode set on the device – nothing to protect with.
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your expenses") { success, _ in
            DispatchQueue.main.async {
                if success { onUnlock() } else { failed = true }
            }
        }
    }
}
