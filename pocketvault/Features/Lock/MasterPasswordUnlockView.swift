import SwiftUI

struct UnlockView: View {
    let compact: Bool
    let onUnlock: () -> Void

    @State private var isAuthenticating = false
    @Environment(BiometricService.self) private var biometricService
    @Environment(LockManager.self) private var lockManager

    init(compact: Bool = false, onUnlock: @escaping () -> Void) {
        self.compact = compact
        self.onUnlock = onUnlock
    }

    var body: some View {
        VStack(spacing: compact ? AppTheme.Spacing.md : AppTheme.Spacing.xl) {
            Image(systemName: biometricService.hasBiometrics ? biometricService.biometryIcon : "lock.fill")
                .font(.system(size: compact ? 40 : 56))
                .foregroundStyle(biometricService.hasBiometrics ? AppTheme.accent : AppTheme.textTertiary)
                .symbolEffect(.pulse, options: .repeating, isActive: isAuthenticating)

            if !compact {
                Text("Vault Locked")
                    .font(.title2)
                    .foregroundStyle(AppTheme.textPrimary)
            } else {
                Text("Locked")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Button {
                authenticate()
            } label: {
                if biometricService.hasBiometrics {
                    Label("Unlock with \(biometricService.biometryName)", systemImage: biometricService.biometryIcon)
                } else {
                    Label("Unlock", systemImage: "lock.open.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .regular : .large)
            .disabled(isAuthenticating)

            if biometricService.biometricsChanged {
                Label("Biometric enrollment changed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            let wasManuallyLocked: Bool
            if let lastLockedAt = lockManager.lastLockedAt {
                wasManuallyLocked = Date().timeIntervalSince(lastLockedAt) < 2
            } else {
                wasManuallyLocked = false
            }
            if !wasManuallyLocked {
                authenticate()
            }
        }
    }

    private func authenticate() {
        isAuthenticating = true
        Task {
            let success = await biometricService.authenticate()
            isAuthenticating = false
            if success {
                onUnlock()
            }
        }
    }
}
