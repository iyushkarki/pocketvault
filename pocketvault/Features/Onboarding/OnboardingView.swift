import SwiftUI

enum OnboardingPage: CaseIterable {
    case welcome
    case features
    case sync
}

struct OnboardingView: View {
    var onComplete: (_ enableSync: Bool) async throws -> Void

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
        isMigrating = true
        Task {
            do {
                try await onComplete(enableSync)
            } catch {
                isMigrating = false
                syncError = error.localizedDescription
                showSyncError = true
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

                Text("Securely manage .env variables from your menu bar.\nYour vault is encrypted on disk and synced via your private iCloud.")
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
                    title: "End-to-End Encryption",
                    subtitle: "AES-GCM with a key stored in your iCloud Keychain"
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
                    subtitle: "Standard .env files and encrypted .pocketvault backups"
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
    @State private var keychainAvailability: ICloudKeychainStatus = .unknown

    private var iCloudKeychainOK: Bool {
        if case .available = keychainAvailability { return true }
        return false
    }

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

                Text("Make your vault available across your Macs.\nRequires iCloud Keychain to securely share the encryption key.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }

            Toggle("Enable iCloud Sync", isOn: $enableSync)
                .toggleStyle(.switch)
                .disabled(!iCloudKeychainOK)
                .frame(maxWidth: 240)

            if !iCloudKeychainOK {
                VStack(spacing: 8) {
                    Label("iCloud Keychain is required for sync.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                    Button("Open System Settings") {
                        ICloudKeychainAvailability.openSystemSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }

            Text("You can change this anytime in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()
        }
        .padding(32)
        .task {
            let status = await Task.detached { ICloudKeychainAvailability.check() }.value
            keychainAvailability = status
        }
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
                    .frame(width: 100)
            } else {
                Button("Back", action: goBack)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(width: 100)
            }

            Spacer()

            OnboardingPageIndicator(currentPage: currentPage)

            Spacer()

            if isLastPage {
                Button(isMigrating ? "Setting up..." : "Get Started", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isMigrating)
                    .frame(minWidth: 140)
            } else {
                Button("Continue", action: goForward)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 140)
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
