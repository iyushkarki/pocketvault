import SwiftUI

enum OnboardingPage: CaseIterable {
    case welcome
    case features
    case sync
}

struct OnboardingView: View {
    var onComplete: () -> Void

    @Environment(SyncService.self) private var syncService
    @State private var currentPage: OnboardingPage = .welcome
    @State private var enableSync = false
    @State private var isMigrating = false
    @State private var syncError: String?
    @State private var showSyncError = false

    var body: some View {
        VStack(spacing: 0) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            OnboardingBottomBar(
                currentPage: $currentPage,
                isMigrating: isMigrating,
                onFinish: completeOnboarding
            )
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
        }
        .frame(
            minWidth: AppTheme.Sizing.windowMinWidth,
            minHeight: AppTheme.Sizing.windowMinHeight
        )
        .alert("Sync Error", isPresented: $showSyncError) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "An error occurred while enabling iCloud sync.")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .welcome:
            OnboardingWelcomePage()
                .transition(.push(from: .trailing))
        case .features:
            OnboardingFeaturesPage()
                .transition(.push(from: .trailing))
        case .sync:
            OnboardingSyncPage(enableSync: $enableSync)
                .transition(.push(from: .trailing))
        }
    }

    private func completeOnboarding() {
        if enableSync {
            isMigrating = true
            Task {
                do {
                    try await syncService.enableSync()
                    UserDefaults.standard.set(true, forKey: AppConfig.UserDefaultsKey.hasCompletedOnboarding)
                    restartApp()
                } catch {
                    isMigrating = false
                    syncError = error.localizedDescription
                    showSyncError = true
                }
            }
        } else {
            UserDefaults.standard.set(true, forKey: AppConfig.UserDefaultsKey.hasCompletedOnboarding)
            onComplete()
        }
    }

    private func restartApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: config
        ) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)

            VStack(spacing: 8) {
                Text("Welcome to Pocket Vault")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Securely manage .env variables from your menu bar.\nSecrets are stored in the macOS Keychain — zero third-party dependencies.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct OnboardingFeaturesPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("What You Get")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "key.fill",
                    color: .orange,
                    title: "Hardware-Backed Encryption",
                    subtitle: "AES-256 via macOS Keychain on Apple Silicon"
                )
                FeatureRow(
                    icon: "touchid",
                    color: .pink,
                    title: "Touch ID Lock",
                    subtitle: "Unlock with biometrics, auto-lock on sleep"
                )
                FeatureRow(
                    icon: "doc.text.fill",
                    color: .blue,
                    title: "Import & Export",
                    subtitle: "Standard .env files and encrypted .envvault backups"
                )
                FeatureRow(
                    icon: "menubar.rectangle",
                    color: .green,
                    title: "Menu Bar Access",
                    subtitle: "Browse projects and copy values in one click"
                )
            }
            .frame(maxWidth: 380)

            Spacer()
        }
        .padding(32)
    }
}

private struct OnboardingSyncPage: View {
    @Binding var enableSync: Bool
    @Environment(SyncService.self) private var syncService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(enableSync ? AppTheme.accent : AppTheme.textTertiary)
                .animation(.easeInOut(duration: 0.2), value: enableSync)

            VStack(spacing: 8) {
                Text("iCloud Sync")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Sync projects and secrets across your Macs via iCloud.\nIf you skip this, your data stays on this device only.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }

            Toggle("Enable iCloud Sync", isOn: $enableSync)
                .toggleStyle(.switch)
                .disabled(!syncService.iCloudAvailable)
                .frame(maxWidth: 240)

            if !syncService.iCloudAvailable {
                Label("Sign into iCloud in System Settings to enable sync.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
            }

            Text("You can change this anytime in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()
        }
        .padding(32)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct OnboardingBottomBar: View {
    @Binding var currentPage: OnboardingPage
    let isMigrating: Bool
    let onFinish: () -> Void

    private var isLastPage: Bool {
        currentPage == OnboardingPage.allCases.last
    }

    private var isFirstPage: Bool {
        currentPage == OnboardingPage.allCases.first
    }

    var body: some View {
        HStack {
            if isFirstPage {
                Spacer()
                    .frame(width: 80)
            } else {
                Button("Back", action: goBack)
                    .buttonStyle(.bordered)
                    .frame(width: 80)
            }

            Spacer()

            OnboardingPageIndicator(currentPage: currentPage)

            Spacer()

            if isLastPage {
                Button(isMigrating ? "Setting up..." : "Get Started", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .disabled(isMigrating)
            } else {
                Button("Continue", action: goForward)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func goBack() {
        guard let index = OnboardingPage.allCases.firstIndex(of: currentPage), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = OnboardingPage.allCases[index - 1]
        }
    }

    private func goForward() {
        guard let index = OnboardingPage.allCases.firstIndex(of: currentPage),
              index < OnboardingPage.allCases.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = OnboardingPage.allCases[index + 1]
        }
    }
}

private struct OnboardingPageIndicator: View {
    let currentPage: OnboardingPage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? AppTheme.accent : AppTheme.textTertiary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
