import Foundation

enum AppConfig {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.pocketvault"
    static let keychainServiceName = "\(bundleIdentifier).keychain"
    static let vaultKeyIdentifier = "pocketvault.master.vaultkey"
    static let canonicalVaultFileName = "PocketVault.vault"

    enum Defaults {
        static let autoLockTimeout: TimeInterval = 300
        static let clipboardClearTimeout: TimeInterval = 30
        static let launchAtLogin = false
        static let cloudKitSyncEnabled = false
        static let lockOnSleep = true
        static let lockOnPopoverClose = false
        static let globalHotkey = "cmd+shift+e"
        static let defaultExportFormat = "env"
        static let hasCompletedOnboarding = false
        static let menuBarVisible = true
    }

    enum UserDefaultsKey {
        static let autoLockTimeout = "autoLockTimeout"
        static let launchAtLogin = "launchAtLogin"
        static let clipboardClearTimeout = "clipboardClearTimeout"
        static let cloudKitSyncEnabled = "cloudKitSyncEnabled"
        static let lockOnSleep = "lockOnSleep"
        static let lockOnPopoverClose = "lockOnPopoverClose"
        static let globalHotkey = "globalHotkey"
        static let defaultExportFormat = "defaultExportFormat"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let biometricDomainState = "biometricDomainState"
        static let deviceIdentity = "deviceIdentity"
        static let lastVaultExportDate = "lastVaultExportDate"
        static let lastSelectedFileID = "lastSelectedFileID"
        static let menuBarVisible = "menuBarVisible"
        static let pendingDataReset = "pendingDataReset"
        static let lastSyncedRevision = "syncCoordinator.lastSyncedRevision"
        static let acknowledgedDeletedRemoteRevision = "syncCoordinator.acknowledgedDeletedRemoteRevision"
    }

    static func markPendingDataReset() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.pendingDataReset)
    }

    @discardableResult
    static func applyPendingDataResetIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: UserDefaultsKey.pendingDataReset) else { return false }

        for key in dataResetUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        return true
    }

    static func clearVaultScopedUserDefaults() {
        let defaults = UserDefaults.standard
        for key in vaultScopedUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    private static let vaultScopedUserDefaultsKeys = [
        UserDefaultsKey.cloudKitSyncEnabled,
        UserDefaultsKey.lastSelectedFileID,
        UserDefaultsKey.lastVaultExportDate,
        UserDefaultsKey.lastSyncedRevision,
        UserDefaultsKey.acknowledgedDeletedRemoteRevision,
    ]

    private static let dataResetUserDefaultsKeys = vaultScopedUserDefaultsKeys + [
        UserDefaultsKey.hasCompletedOnboarding,
        UserDefaultsKey.deviceIdentity,
        UserDefaultsKey.biometricDomainState,
        UserDefaultsKey.pendingDataReset,
    ]
}
