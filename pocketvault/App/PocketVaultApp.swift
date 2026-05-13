import SwiftUI
import SwiftData
import AppKit
import os

@main
struct PocketVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var lockManager = LockManager()
    @State private var biometricService = BiometricService()
    @State private var syncCoordinator = SyncCoordinator.shared
    @State private var dataManager: DataManager?
    @State private var vaultRecoveryError: String?
    @State private var showVaultRecovery = false
    @AppStorage(AppConfig.UserDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = AppConfig.Defaults.hasCompletedOnboarding
    @AppStorage(AppConfig.UserDefaultsKey.menuBarVisible) private var menuBarVisible = AppConfig.Defaults.menuBarVisible

    init() {
        let didApplyPendingDataReset = AppConfig.applyPendingDataResetIfNeeded()

        let hasCompletedOnboarding = didApplyPendingDataReset ? false : UserDefaults.standard.object(forKey: AppConfig.UserDefaultsKey.hasCompletedOnboarding) as? Bool
            ?? AppConfig.Defaults.hasCompletedOnboarding
        if hasCompletedOnboarding {
            _dataManager = State(initialValue: DataManager())
        } else {
            _dataManager = State(initialValue: nil)
        }
    }

    var body: some Scene {
        mainWindowScene
        menuBarScene
        settingsScene
    }

    @SceneBuilder
    private var mainWindowScene: some Scene {
        Window("Pocket Vault", id: "main") {
            Group {
                if hasCompletedOnboarding {
                    if let dataManager {
                        MainWindowView()
                            .modelContainer(dataManager.container)
                    } else {
                        LoadingStateView(message: "Loading Pocket Vault...")
                    }
                } else {
                    OnboardingView(onComplete: completeOnboarding)
                }
            }
            .environment(lockManager)
            .environment(biometricService)
            .environment(syncCoordinator)
            .background(MainWindowCloseHandler())
            .task {
                bootstrapDataManagerIfNeeded()
                if !hasCompletedOnboarding {
                    activateOnboardingWindow()
                }
            }
            .alert("Vault Cannot Be Opened", isPresented: $showVaultRecovery, presenting: vaultRecoveryError) { _ in
                Button("Reset Vault on This Mac", role: .destructive) { resetCorruptedVault() }
                Button("Quit", role: .cancel) { NSApp.terminate(nil) }
            } message: { message in
                Text("\(message)\n\nResetting will move the unreadable vault aside and start fresh on this Mac. If iCloud Sync is enabled, your data will be restored from iCloud.")
            }
        }
        .defaultSize(
            width: AppTheme.Sizing.windowDefaultWidth,
            height: AppTheme.Sizing.windowDefaultHeight
        )
        .defaultPosition(.center)
        .commands {
            CommandMenu("Vault") {
                Button("New Project") {
                    NotificationCenter.default.post(name: .pocketVaultNewProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New File") {
                    NotificationCenter.default.post(name: .pocketVaultNewFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Rename File") {
                    NotificationCenter.default.post(name: .pocketVaultRenameFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Delete File") {
                    NotificationCenter.default.post(name: .pocketVaultDeleteFile, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Import .env File...") {
                    NotificationCenter.default.post(name: .pocketVaultImportEnvFile, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Lock Vault") {
                    NotificationCenter.default.post(name: .pocketVaultLock, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }

    @SceneBuilder
    private var menuBarScene: some Scene {
        MenuBarExtra(
            "Pocket Vault",
            image: "StatusBarIcon",
            isInserted: Binding(
                get: { hasCompletedOnboarding && menuBarVisible },
                set: { newValue in
                    if hasCompletedOnboarding {
                        menuBarVisible = newValue
                    }
                }
            )
        ) {
            Group {
                if let dataManager {
                    MenuBarView()
                        .modelContainer(dataManager.container)
                } else {
                    LoadingStateView(message: "Loading Pocket Vault...")
                }
            }
            .environment(lockManager)
            .environment(biometricService)
            .environment(syncCoordinator)
        }
        .menuBarExtraStyle(.window)
    }

    @SceneBuilder
    private var settingsScene: some Scene {
        Settings {
            Group {
                if hasCompletedOnboarding {
                    if let dataManager {
                        SettingsView()
                            .modelContainer(dataManager.container)
                    } else {
                        LoadingStateView(message: "Loading settings...")
                    }
                } else {
                    SettingsSetupView()
                }
            }
                .environment(lockManager)
                .environment(biometricService)
                .environment(syncCoordinator)
                .task {
                    bootstrapDataManagerIfNeeded()
                }
        }
    }

    private func bootstrapDataManagerIfNeeded() {
        guard hasCompletedOnboarding else { return }

        if dataManager == nil {
            dataManager = DataManager()
        }

        guard let dataManager else { return }

        do {
            try VaultRepository.shared.bootstrap(container: dataManager.container)
            SyncCoordinator.shared.bootstrap(container: dataManager.container)
        } catch let error as EncryptedVaultStoreError {
            if case .unrecoverable = error {
                vaultRecoveryError = error.localizedDescription
                showVaultRecovery = true
            }
            Logger(subsystem: AppConfig.bundleIdentifier, category: "PocketVaultApp")
                .error("VaultRepository bootstrap failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            Logger(subsystem: AppConfig.bundleIdentifier, category: "PocketVaultApp")
                .error("VaultRepository bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resetCorruptedVault() {
        do {
            _ = try EncryptedVaultStore.shared.quarantineCorruptVault()
        } catch {
            Logger(subsystem: AppConfig.bundleIdentifier, category: "PocketVaultApp")
                .error("Quarantine failed: \(error.localizedDescription, privacy: .public)")
        }
        showVaultRecovery = false
        vaultRecoveryError = nil
        bootstrapDataManagerIfNeeded()
    }

    private func completeOnboarding(enableSync: Bool) async throws {
        let manager = DataManager()
        dataManager = manager

        try VaultRepository.shared.bootstrap(container: manager.container)
        SyncCoordinator.shared.bootstrap(container: manager.container)

        if enableSync {
            await SyncCoordinator.shared.startSync()
        }

        hasCompletedOnboarding = true
    }

    private func activateOnboardingWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProgressView()
            Text(message)
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.lg)
    }
}

private struct SettingsSetupView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "gear")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textTertiary)

            Text("Complete setup first")
                .font(AppTheme.Fonts.title)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Pocket Vault settings become available after onboarding is complete.")
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 420, height: 220)
        .padding(AppTheme.Spacing.xl)
    }
}
