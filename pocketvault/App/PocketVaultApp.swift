import SwiftUI
import SwiftData

@main
struct PocketVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var lockManager = LockManager()
    @State private var biometricService = BiometricService()
    @State private var syncService = SyncService()
    @AppStorage(AppConfig.UserDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = AppConfig.Defaults.hasCompletedOnboarding

    var body: some Scene {
        MenuBarExtra("Pocket Vault", image: "StatusBarIcon") {
            MenuBarView()
                .modelContainer(DataManager.shared.container)
                .environment(lockManager)
                .environment(biometricService)
                .environment(syncService)
                .task {
                    syncService.checkStatus()
                    if syncService.isEnabled {
                        let context = ModelContext(DataManager.shared.container)
                        _ = try? syncService.resolveDuplicates(in: context)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Pocket Vault", id: "main") {
            Group {
                if hasCompletedOnboarding {
                    MainWindowView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .modelContainer(DataManager.shared.container)
            .environment(lockManager)
            .environment(biometricService)
            .environment(syncService)
            .onAppear {
                if !hasCompletedOnboarding {
                    try? KeychainService.shared.deleteAll()
                }
                DispatchQueue.main.async {
                    appDelegate.showMainWindow()
                }
            }
            .onDisappear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appDelegate.hideFromDock()
                }
            }
        }
        .defaultSize(
            width: AppTheme.Sizing.windowDefaultWidth,
            height: AppTheme.Sizing.windowDefaultHeight
        )
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .modelContainer(DataManager.shared.container)
                .environment(biometricService)
                .environment(syncService)
        }
    }
}
