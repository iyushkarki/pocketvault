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
        .frame(width: 450, height: 350)
    }
}

private struct GeneralSettingsView: View {
    @Environment(SyncService.self) private var syncService
    @AppStorage(AppConfig.UserDefaultsKey.launchAtLogin) private var launchAtLogin = AppConfig.Defaults.launchAtLogin

    @State private var syncToggleValue = UserDefaults.standard.bool(forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
    @State private var isMigrating = false
    @State private var showRestartAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

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
                Toggle("Sync with iCloud", isOn: $syncToggleValue)
                    .disabled(isMigrating || (!syncService.iCloudAvailable && !syncToggleValue))
                    .onChange(of: syncToggleValue) { _, newValue in
                        Task { await toggleSync(newValue) }
                    }

                syncStatusRow
            }
        }
        .formStyle(.grouped)
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                restartApp()
            }
        } message: {
            Text("Pocket Vault needs to restart to apply sync changes.")
        }
        .alert("Sync Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            syncService.checkStatus()
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch syncService.status {
        case .disabled:
            HStack {
                Text("Status")
                Spacer()
                Text("Off")
                    .foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            HStack {
                Text("Status")
                Spacer()
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        case .migrating:
            HStack {
                Text("Status")
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Migrating...")
                    .foregroundStyle(.secondary)
            }
        case .synced:
            HStack {
                Text("Status")
                Spacer()
                Label("Synced", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        case .error(let message):
            HStack {
                Text("Status")
                Spacer()
                Label(message, systemImage: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private func toggleSync(_ enabled: Bool) async {
        isMigrating = true
        defer { isMigrating = false }

        do {
            if enabled {
                try await syncService.enableSync()
            } else {
                try await syncService.disableSync()
            }
            showRestartAlert = true
        } catch {
            syncToggleValue = !enabled
            errorMessage = error.localizedDescription
            showErrorAlert = true
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

private struct SecuritySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppConfig.UserDefaultsKey.autoLockTimeout) private var autoLockTimeout: TimeInterval = AppConfig.Defaults.autoLockTimeout
    @AppStorage(AppConfig.UserDefaultsKey.lockOnSleep) private var lockOnSleep: Bool = AppConfig.Defaults.lockOnSleep
    @AppStorage(AppConfig.UserDefaultsKey.clipboardClearTimeout) private var clipboardClearTimeout: TimeInterval = AppConfig.Defaults.clipboardClearTimeout

    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showWipeRestartAlert = false
    @State private var wipeError: String?
    @State private var showWipeErrorAlert = false

    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "Settings"
    )

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

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete All Data")
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Permanently deletes all projects, files, entries, and Keychain secrets. This cannot be undone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                showFinalDeleteConfirmation = true
            }
        } message: {
            Text("This will permanently delete all projects, files, entries, and stored secrets from this device and iCloud Keychain. This cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showFinalDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                performSecureWipe()
            }
        } message: {
            Text("All data will be permanently erased from this device and iCloud Keychain. Export a backup first if you want to keep your data.")
        }
        .alert("Delete Failed", isPresented: $showWipeErrorAlert, presenting: wipeError) { _ in
            Button("OK") { wipeError = nil }
        } message: { message in
            Text(message)
        }
        .alert("All Data Deleted", isPresented: $showWipeRestartAlert) {
            Button("Restart Now") {
                restartApp()
            }
        } message: {
            Text("All data has been erased. Pocket Vault will now restart.")
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

    private func performSecureWipe() {
        isDeleting = true
        logger.warning("Secure data wipe initiated by user")

        do {
            try KeychainService.shared.deleteAll()
            logger.info("Keychain data deleted")
        } catch {
            logger.error("Failed to delete Keychain data: \(error.localizedDescription)")
            wipeError = "Failed to delete stored secrets: \(error.localizedDescription)"
            showWipeErrorAlert = true
            isDeleting = false
            return
        }

        do {
            try modelContext.delete(model: EnvEntry.self)
            try modelContext.delete(model: EnvFile.self)
            try modelContext.delete(model: Project.self)
            try modelContext.save()
            logger.info("SwiftData models deleted")
        } catch {
            logger.error("Failed to delete SwiftData: \(error.localizedDescription)")
            wipeError = "Failed to delete saved metadata: \(error.localizedDescription)"
            showWipeErrorAlert = true
            isDeleting = false
            return
        }

        let domain = Bundle.main.bundleIdentifier ?? AppConfig.bundleIdentifier
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        logger.info("UserDefaults cleared")

        logger.warning("Secure data wipe completed")
        isDeleting = false
        showWipeRestartAlert = true
    }
}

private struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)

            Text("Pocket Vault")
                .font(.title2.bold())

            Text("Version \(appVersion) (\(buildNumber))")
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
