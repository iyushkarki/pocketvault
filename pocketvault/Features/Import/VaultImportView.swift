import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct VaultImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var fileURL: URL?
    @State private var password = ""
    @State private var importedSnapshot: VaultSnapshot?
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var importResult: (projects: Int, files: Int, entries: Int)?

    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "VaultImport"
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480)
        .frame(minHeight: 300)
        .onDisappear { clearSecrets() }
    }

    private var header: some View {
        HStack {
            Text("Import Encrypted Backup")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let result = importResult {
            importCompleteView(result)
        } else if let snapshot = importedSnapshot {
            vaultPreview(snapshot)
        } else if fileURL != nil {
            passwordEntry
        } else {
            filePickerPrompt
        }
    }

    private var filePickerPrompt: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textTertiary)
            Text("Choose a .pocketvault backup to import")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
            Button("Choose File...") { pickFile() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var passwordEntry: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.textTertiary)

            Text("Enter the password used to encrypt this vault.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: AppTheme.Spacing.sm) {
                SecureField("Encryption Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { decrypt() }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.error)
                }

                Button("Decrypt") { decrypt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isProcessing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func vaultPreview(_ snapshot: VaultSnapshot) -> some View {
        VStack(spacing: 0) {
            List {
                ForEach(snapshot.projects) { project in
                    DisclosureGroup {
                        ForEach(project.files) { file in
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(AppTheme.textTertiary)
                                Text(file.name)
                                    .font(AppTheme.Fonts.body)
                                Spacer()
                                Text("\(file.entries.filter { !$0.isComment }.count) entries")
                                    .font(AppTheme.Fonts.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text(project.name)
                                .font(AppTheme.Fonts.sectionHeader)
                            Spacer()
                            Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s")")
                                .font(AppTheme.Fonts.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.textTertiary)
                Text("Importing will merge new projects into your vault. Existing data is preserved.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }

    private func importCompleteView(_ result: (projects: Int, files: Int, entries: Int)) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.success)

            Text("Import Complete")
                .font(.title3.bold())

            VStack(spacing: AppTheme.Spacing.xs) {
                Text("\(result.projects) project\(result.projects == 1 ? "" : "s")")
                Text("\(result.files) file\(result.files == 1 ? "" : "s")")
                Text("\(result.entries) entries")
            }
            .font(.body)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            if fileURL != nil && importedSnapshot == nil && importResult == nil {
                Button("Choose Different File...") { pickFile() }
            }

            Spacer()

            if importResult != nil {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if importedSnapshot != nil {
                Button("Import All") { performImport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isProcessing)
            }
        }
        .padding()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Pocket Vault Backup"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        password = ""
        importedSnapshot = nil
        errorMessage = nil
        importResult = nil
    }

    private func clearSecrets() {
        password = ""
        importedSnapshot = nil
    }

    private func decrypt() {
        errorMessage = nil
        isProcessing = true

        do {
            guard let url = fileURL else { return }
            let encryptedData = try Data(contentsOf: url)
            let decrypted = try CryptoService.decryptVault(encryptedData, password: password)
            password = ""
            let snapshot = try BackupService.parseBackup(decrypted)
            importedSnapshot = snapshot
            logger.info("Vault decrypted successfully")
        } catch {
            if error is CryptoError {
                errorMessage = error.localizedDescription
            } else if let backupError = error as? BackupServiceError {
                errorMessage = backupError.localizedDescription
            } else {
                errorMessage = "Failed to read vault file."
            }
        }

        isProcessing = false
    }

    private func performImport() {
        guard let incoming = importedSnapshot else { return }
        isProcessing = true

        do {
            let current = VaultRepository.shared.snapshot
            let merged = BackupService.mergeIntoCurrent(incoming, current: current)
            try VaultRepository.shared.replaceSnapshot(merged)

            let projectsAdded = incoming.projectCount
            let filesAdded = incoming.fileCount
            let entriesAdded = incoming.entryCount
            importedSnapshot = nil
            importResult = (projectsAdded, filesAdded, entriesAdded)
            logger.info("Vault imported: \(projectsAdded) projects, \(filesAdded) files, \(entriesAdded) entries")
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}
