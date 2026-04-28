import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct VaultExportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isProcessing = false

    private let snapshot: VaultSnapshot = VaultRepository.shared.snapshot

    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "VaultExport"
    )

    private var canExport: Bool {
        password.count >= 8
            && password == confirmPassword
            && snapshot.hasData
            && !isProcessing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: true)
        .onDisappear { clearSecrets() }
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent)

            Text("Export Encrypted Backup")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)

            Text("All \(snapshot.projectCount) project\(snapshot.projectCount == 1 ? "" : "s") will be encrypted\nwith the password you provide.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, AppTheme.Spacing.lg)
        .padding(.horizontal, AppTheme.Spacing.xl)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Encryption Password")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                SecureField("Enter password (8+ characters)", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Confirm Password")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)

                if !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundStyle(AppTheme.error)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.textTertiary)
                Text("Use a strong, unique password and store it safely. You'll need this password to import the vault on any device.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Export...") { performExport() }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
                .keyboardShortcut(.defaultAction)
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func clearSecrets() {
        password = ""
        confirmPassword = ""
    }

    private func performExport() {
        errorMessage = nil
        isProcessing = true

        do {
            let plaintext = try BackupService.makeBackup(from: snapshot)
            let encrypted = try CryptoService.encryptVault(plaintext, password: password)

            clearSecrets()

            let panel = NSSavePanel()
            panel.title = "Save Pocket Vault Backup"
            panel.nameFieldStringValue = "pocketvault-backup.pocketvault"
            panel.allowedContentTypes = [.data]

            guard panel.runModal() == .OK, let url = panel.url else {
                isProcessing = false
                return
            }

            try encrypted.write(to: url)
            UserDefaults.standard.set(Date(), forKey: AppConfig.UserDefaultsKey.lastVaultExportDate)
            logger.info("Vault exported successfully (\(self.snapshot.projectCount) projects)")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Vault export failed: \(error.localizedDescription)")
            clearSecrets()
        }

        isProcessing = false
    }
}
