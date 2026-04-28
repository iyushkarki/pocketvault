import SwiftUI
import SwiftData
import ServiceManagement
import os

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SecuritySettingsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 360)
    }
}

private struct GeneralSettingsView: View {
    @Environment(LockManager.self) private var lockManager
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @AppStorage(AppConfig.UserDefaultsKey.launchAtLogin) private var launchAtLogin = AppConfig.Defaults.launchAtLogin

    @State private var keychainAvailability: ICloudKeychainStatus = .unknown
    @State private var errorMessage: String?
    @State private var showError = false

    private var iCloudKeychainOK: Bool {
        if case .available = keychainAvailability { return true }
        return false
    }

    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { syncCoordinator.isEnabled },
            set: { newValue in
                if newValue {
                    Task { await enableSync() }
                } else {
                    disableSync()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section("iCloud Sync") {
                Toggle("Sync with iCloud", isOn: syncEnabledBinding)
                    .disabled(lockManager.isLocked || (!iCloudKeychainOK && !syncCoordinator.isEnabled))

                syncStatusRow

                if case .needsAttention(.remoteUnreadable) = syncCoordinator.state {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The vault stored in iCloud was encrypted with a key this Mac doesn't have. This usually happens after the app was reinstalled or vault data was wiped.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Overwrite iCloud with This Mac") {
                                Task { await syncCoordinator.overwriteRemoteWithLocal() }
                            }
                            Button("Turn Off Sync") {
                                disableSync()
                            }
                        }
                    }
                }

                if !iCloudKeychainOK {
                    HStack(spacing: 6) {
                        Label("iCloud Keychain is required.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open System Settings") {
                            ICloudKeychainAvailability.openSystemSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                } else if syncCoordinator.isEnabled {
                    Text("Your vault is available across your Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your vault stays only on this Mac until you turn on iCloud Sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Sync Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            let status = await Task.detached { ICloudKeychainAvailability.check() }.value
            keychainAvailability = status
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch syncCoordinator.state {
        case .off:
            statusLine(text: "Only on This Mac", color: .secondary)
        case .ready:
            statusLine(label: Label("Available on Your Macs", systemImage: "checkmark.icloud.fill"), color: .green)
        case .syncing:
            HStack {
                Text("Status")
                Spacer()
                ProgressView().controlSize(.small)
                Text("Syncing").foregroundStyle(.secondary)
            }
        case .conflict:
            statusLine(label: Label("Conflict — open the menu bar to resolve", systemImage: "exclamationmark.triangle.fill"), color: .orange)
        case .remoteDeleted:
            statusLine(label: Label("Remote vault deleted — open the menu bar to resolve", systemImage: "trash.circle.fill"), color: .orange)
        case .needsAttention(let kind):
            statusLine(label: Label(message(for: kind), systemImage: "exclamationmark.icloud.fill"), color: .red)
        }
    }

    private func statusLine(text: String, color: Color) -> some View {
        HStack {
            Text("Status")
            Spacer()
            Text(text).foregroundStyle(color)
        }
    }

    private func statusLine(label: Label<Text, Image>, color: Color) -> some View {
        HStack {
            Text("Status")
            Spacer()
            label.foregroundStyle(color).font(.callout)
        }
    }

    private func message(for kind: SyncCoordinator.IssueKind) -> String {
        switch kind {
        case .iCloudKeychainUnavailable(let reason): return reason
        case .cloudKitAccountUnavailable(let m): return m
        case .remoteUnreadable: return "iCloud copy can't be read on this Mac."
        case .syncError(let m): return m
        }
    }

    private func enableSync() async {
        let status = await Task.detached { ICloudKeychainAvailability.check() }.value
        keychainAvailability = status
        guard iCloudKeychainOK else {
            errorMessage = "Sign in to iCloud and enable iCloud Keychain in System Settings."
            showError = true
            return
        }
        await syncCoordinator.startSync()
    }

    private func disableSync() {
        syncCoordinator.stopSync()
    }
}

private struct SecuritySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @AppStorage(AppConfig.UserDefaultsKey.autoLockTimeout) private var autoLockTimeout: TimeInterval = AppConfig.Defaults.autoLockTimeout
    @AppStorage(AppConfig.UserDefaultsKey.lockOnSleep) private var lockOnSleep: Bool = AppConfig.Defaults.lockOnSleep
    @AppStorage(AppConfig.UserDefaultsKey.clipboardClearTimeout) private var clipboardClearTimeout: TimeInterval = AppConfig.Defaults.clipboardClearTimeout

    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showWipeRestartAlert = false
    @State private var wipeError: String?
    @State private var showWipeErrorAlert = false
    @State private var selectedDeleteScope: DeleteExecutionScope = .thisMacOnly

    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "Settings")

    private let lockTimeoutOptions: [(String, TimeInterval)] = [
        ("Never", 0),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
    ]

    private let clipboardOptions: [(String, TimeInterval)] = [
        ("Never", 0),
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
    ]

    private var dangerZoneFooterText: String {
        if lockManager.isLocked {
            return "Unlock Pocket Vault in the main window before deleting data."
        }
        return "Permanently deletes all projects, files, entries, and the encrypted vault. This cannot be undone."
    }

    private var deleteConfirmationTitle: String {
        selectedDeleteScope == .everywhere ? "Delete Vault Everywhere?" : "Delete Data on This Mac?"
    }

    private var deleteConfirmationMessage: String {
        switch selectedDeleteScope {
        case .thisMacOnly:
            return "This removes Pocket Vault data stored on this Mac. Cloud-backed data is not touched."
        case .everywhere:
            return "This deletes your iCloud-synced Pocket Vault data and removes it from this Mac. Other Macs will see a prompt to keep their local copy or wipe it."
        }
    }

    var body: some View {
        Form {
            Section("Auto-Lock") {
                Picker("Lock after inactivity:", selection: $autoLockTimeout) {
                    ForEach(lockTimeoutOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Toggle("Lock on system sleep", isOn: $lockOnSleep)
            }

            Section("Clipboard") {
                Picker("Clear clipboard after:", selection: $clipboardClearTimeout) {
                    ForEach(clipboardOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
            }

            dangerZoneSection
        }
        .formStyle(.grouped)
        .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                showFinalDeleteConfirmation = true
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(deleteConfirmationTitle, isPresented: $showFinalDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(selectedDeleteScope.confirmButtonTitle, role: .destructive) {
                Task { await performSecureWipe(scope: selectedDeleteScope) }
            }
        } message: {
            Text("Export an encrypted backup first if you may need to restore this vault later.")
        }
        .alert("Delete Failed", isPresented: $showWipeErrorAlert, presenting: wipeError) { _ in
            Button("OK") { wipeError = nil }
        } message: { message in
            Text(message)
        }
        .alert("All Data Deleted", isPresented: $showWipeRestartAlert) {
            if AppRelauncher.requiresManualRestartFromDebugger {
                Button("Quit Now") { AppRelauncher.restart() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("Restart Now") { AppRelauncher.restart() }
            }
        } message: {
            Text(wipeRestartHelpText)
        }
    }

    private var wipeRestartHelpText: String {
        if AppRelauncher.requiresManualRestartFromDebugger {
            return "All data has been erased. Because Pocket Vault is running from Xcode, click Quit Now, then press Run again in Xcode for a clean launch."
        }
        return "All data has been erased. Pocket Vault will now restart."
    }

    private var dangerZoneSection: some View {
        Section {
            if syncCoordinator.isEnabled {
                Button(role: .destructive) {
                    selectedDeleteScope = .everywhere
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete iCloud Vault Everywhere...")
                    }
                }
                .disabled(isDeleting || lockManager.isLocked)

                Text("Turn off iCloud Sync first if you only want to keep data on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(role: .destructive) {
                    selectedDeleteScope = .thisMacOnly
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete Data on This Mac...")
                    }
                }
                .disabled(isDeleting || lockManager.isLocked)
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text(dangerZoneFooterText).foregroundStyle(.secondary)
        }
    }

    private func performSecureWipe(scope: DeleteExecutionScope) async {
        isDeleting = true
        logger.warning("Secure data wipe initiated by user (scope=\(scope.rawValue, privacy: .public))")
        lockManager.lock()
        ClipboardManager.shared.clearImmediately()

        syncCoordinator.stopSync()

        if scope == .everywhere {
            do {
                try await syncCoordinator.deleteRemoteVault()
            } catch {
                wipeError = "Failed to delete iCloud vault: \(error.localizedDescription)"
                showWipeErrorAlert = true
                isDeleting = false
                return
            }
        }

        do {
            switch scope {
            case .everywhere:
                try VaultRepository.shared.wipeEverything()
            case .thisMacOnly:
                try VaultRepository.shared.wipeLocalDataKeepingCloudKey()
            }
        } catch {
            wipeError = "Failed to delete vault: \(error.localizedDescription)"
            showWipeErrorAlert = true
            isDeleting = false
            return
        }

        let domain = Bundle.main.bundleIdentifier ?? AppConfig.bundleIdentifier
        switch scope {
        case .everywhere:
            UserDefaults.standard.removePersistentDomain(forName: domain)
        case .thisMacOnly:
            let vaultScopedKeys = [
                AppConfig.UserDefaultsKey.cloudKitSyncEnabled,
                AppConfig.UserDefaultsKey.lastSelectedFileID,
                AppConfig.UserDefaultsKey.lastVaultExportDate,
                "syncCoordinator.lastSyncedRevision",
            ]
            for key in vaultScopedKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.synchronize()

        logger.warning("Secure data wipe completed")
        isDeleting = false
        showWipeRestartAlert = true
    }
}

private enum DeleteExecutionScope: String, Identifiable {
    case thisMacOnly
    case everywhere

    var id: String { rawValue }

    var confirmButtonTitle: String {
        switch self {
        case .thisMacOnly: return "Delete This Mac Data"
        case .everywhere: return "Delete Everywhere"
        }
    }
}

private struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)

            Text("Pocket Vault")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Secure environment variable manager\nfor macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
