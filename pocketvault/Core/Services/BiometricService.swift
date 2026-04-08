import LocalAuthentication
import os

@Observable
final class BiometricService {
    private(set) var biometryType: LABiometryType = .none
    private(set) var biometricsChanged = false

    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "BiometricService"
    )

    init() {
        checkBiometryType()
        checkDomainState()
    }

    var biometryName: String {
        switch biometryType {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        case .none: "Biometrics"
        @unknown default: "Biometrics"
        }
    }

    var biometryIcon: String {
        switch biometryType {
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        case .none: "lock.fill"
        @unknown default: "lock.fill"
        }
    }

    var hasBiometrics: Bool {
        biometryType != .none
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Pocket Vault"
            )

            if success {
                updateStoredDomainState(context)
                biometricsChanged = false
                logger.info("Authentication succeeded")
            }

            return success
        } catch {
            logger.warning("Authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    private func checkBiometryType() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometryType = context.biometryType
        } else {
            biometryType = .none
        }
    }

    private func checkDomainState() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }

        let currentState = context.domainState.stateHash
        let stored = UserDefaults.standard.data(forKey: AppConfig.UserDefaultsKey.biometricDomainState)

        if let stored, stored != currentState {
            biometricsChanged = true
            logger.warning("Biometric enrollment changed — forcing re-authentication")
        }
    }

    private func updateStoredDomainState(_ context: LAContext) {
        let state = context.domainState.stateHash
        UserDefaults.standard.set(state, forKey: AppConfig.UserDefaultsKey.biometricDomainState)
    }
}
