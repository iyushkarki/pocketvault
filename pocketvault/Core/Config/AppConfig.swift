import Foundation

enum AppConfig {
    static let bundleIdentifier = "app.pocketvault"
    static let keychainServiceName = "app.pocketvault.keychain"
    static let keychainIdentifierPrefix = "pocketvault"

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
        static let lastKeychainCleanup = "lastKeychainCleanup"
        static let keychainMigrationComplete = "keychainMigrationComplete"
        static let keychainMigrationProgress = "keychainMigrationProgress"
        static let biometricDomainState = "biometricDomainState"
        static let lastVaultExportDate = "lastVaultExportDate"
    }
}
