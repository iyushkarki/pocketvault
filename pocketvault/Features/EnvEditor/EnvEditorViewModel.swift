import SwiftData
import SwiftUI
import os

@Observable
final class EnvEditorViewModel {
    private struct SecretSnapshot {
        let identifier: String
        let value: String?
    }

    private let keychainService: KeychainServiceProtocol
    private(set) var revealedValues: [String: String] = [:]
    var errorMessage: String?
    var lockManager: LockManager?

    @ObservationIgnored
    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "EnvEditor"
    )

    init(keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.keychainService = keychainService
    }

    func toggleReveal(for entry: EnvEntry) {
        lockManager?.recordActivity()
        if revealedValues[entry.keychainIdentifier] != nil {
            revealedValues.removeValue(forKey: entry.keychainIdentifier)
        } else {
            do {
                if let value = try keychainService.getValue(for: entry.keychainIdentifier) {
                    revealedValues[entry.keychainIdentifier] = value
                } else {
                    revealedValues[entry.keychainIdentifier] = ""
                }
                logger.debug("Value revealed for key: \(entry.key)")
            } catch {
                errorMessage = "Failed to read value: \(error.localizedDescription)"
            }
        }
    }

    func revealedValue(for entry: EnvEntry) -> String? {
        revealedValues[entry.keychainIdentifier]
    }

    func copyValue(for entry: EnvEntry) {
        lockManager?.recordActivity()
        do {
            if let value = try keychainService.getValue(for: entry.keychainIdentifier) {
                ClipboardManager.shared.copyToClipboard(value)
                logger.debug("Value copied for key: \(entry.key)")
            }
        } catch {
            errorMessage = "Failed to copy value: \(error.localizedDescription)"
        }
    }

    func copyKeyValue(for entry: EnvEntry) {
        lockManager?.recordActivity()
        do {
            guard let value = try keychainService.getValue(for: entry.keychainIdentifier) else {
                throw VaultError.missingSecret(entry.key)
            }
            let formatted = EnvParser.format([(key: entry.key, value: value)])
            ClipboardManager.shared.copyToClipboard(formatted)
        } catch {
            errorMessage = "Failed to copy: \(error.localizedDescription)"
        }
    }

    func copyKey(for entry: EnvEntry) {
        lockManager?.recordActivity()
        ClipboardManager.shared.copyToClipboard(entry.key)
    }

    func addEntry(key: String, value: String, to file: EnvFile, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        let sortOrder = ((file.entries ?? []).map(\.sortOrder).max() ?? -1) + 1
        let entry = EnvEntry(key: key, sortOrder: sortOrder)
        entry.file = file
        context.insert(entry)

        do {
            try keychainService.setValue(value, for: entry.keychainIdentifier)
            file.updatedAt = .now
            try context.save()
            return true
        } catch {
            context.rollback()
            try? keychainService.deleteValue(for: entry.keychainIdentifier)
            context.delete(entry)
            errorMessage = "Failed to save entry: \(error.localizedDescription)"
            return false
        }
    }

    func updateEntry(_ entry: EnvEntry, key: String, value: String, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        let originalKey = entry.key
        let originalUpdatedAt = entry.updatedAt
        let originalFileUpdatedAt = entry.file?.updatedAt
        let originalSecret: String?

        do {
            originalSecret = try keychainService.getValue(for: entry.keychainIdentifier)
        } catch {
            errorMessage = "Failed to update entry: \(error.localizedDescription)"
            return false
        }

        entry.key = key
        entry.updatedAt = .now
        entry.file?.updatedAt = .now

        do {
            try keychainService.setValue(value, for: entry.keychainIdentifier)
            if revealedValues[entry.keychainIdentifier] != nil {
                revealedValues[entry.keychainIdentifier] = value
            }
            try context.save()
            return true
        } catch {
            entry.key = originalKey
            entry.updatedAt = originalUpdatedAt
            if let originalFileUpdatedAt {
                entry.file?.updatedAt = originalFileUpdatedAt
            }
            if let originalSecret {
                try? keychainService.setValue(originalSecret, for: entry.keychainIdentifier)
                if revealedValues[entry.keychainIdentifier] != nil {
                    revealedValues[entry.keychainIdentifier] = originalSecret
                }
            } else {
                try? keychainService.deleteValue(for: entry.keychainIdentifier)
                revealedValues.removeValue(forKey: entry.keychainIdentifier)
            }
            errorMessage = "Failed to update entry: \(error.localizedDescription)"
            return false
        }
    }

    func deleteEntry(_ entry: EnvEntry, context: ModelContext) {
        lockManager?.recordActivity()
        errorMessage = nil
        let snapshots: [SecretSnapshot]

        do {
            snapshots = try secretSnapshots(for: [entry])
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
            return
        }

        do {
            entry.file?.updatedAt = .now
            try deleteSecrets(using: snapshots)
            context.delete(entry)
            try context.save()
            removeRevealedValues(for: snapshots)
        } catch {
            context.rollback()
            restoreSecretsIfNeeded(from: snapshots)
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }
    }

    func deleteFile(_ file: EnvFile, context: ModelContext) throws {
        let entries = file.entries ?? []
        let snapshots = try secretSnapshots(for: entries)

        do {
            try deleteSecrets(using: snapshots)
            file.project?.updatedAt = .now
            context.delete(file)
            try context.save()
            removeRevealedValues(for: snapshots)
        } catch {
            context.rollback()
            restoreSecretsIfNeeded(from: snapshots)
            throw error
        }
    }

    func deleteProject(_ project: Project, context: ModelContext) throws {
        let entries = (project.files ?? []).flatMap { $0.entries ?? [] }
        let snapshots = try secretSnapshots(for: entries)

        do {
            try deleteSecrets(using: snapshots)
            context.delete(project)
            try context.save()
            removeRevealedValues(for: snapshots)
        } catch {
            context.rollback()
            restoreSecretsIfNeeded(from: snapshots)
            throw error
        }
    }

    func moveEntries(in file: EnvFile, from source: IndexSet, to destination: Int, context: ModelContext) {
        var sorted = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in sorted.enumerated() {
            entry.sortOrder = index
        }
        do {
            try context.save()
        } catch {
            errorMessage = "Failed to save reorder: \(error.localizedDescription)"
        }
    }

    func duplicateKeys(in file: EnvFile) -> Set<String> {
        let keys = (file.entries ?? []).filter { !$0.isComment }.map(\.key)
        var seen = Set<String>()
        var duplicates = Set<String>()
        for key in keys {
            if seen.contains(key) {
                duplicates.insert(key)
            }
            seen.insert(key)
        }
        return duplicates
    }

    func currentValue(for entry: EnvEntry) -> String {
        if let revealed = revealedValues[entry.keychainIdentifier] {
            return revealed
        }
        do {
            guard let value = try keychainService.getValue(for: entry.keychainIdentifier) else {
                throw VaultError.missingSecret(entry.key)
            }
            return value
        } catch {
            errorMessage = "Failed to read value: \(error.localizedDescription)"
            return ""
        }
    }

    func requiredValue(for entry: EnvEntry) throws -> String {
        if let revealed = revealedValues[entry.keychainIdentifier] {
            return revealed
        }
        guard let value = try keychainService.getValue(for: entry.keychainIdentifier) else {
            throw VaultError.missingSecret(entry.key)
        }
        return value
    }

    func hideAllValues() {
        revealedValues.removeAll()
    }

    func rawText(for file: EnvFile) throws -> String {
        let sorted = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var lines: [String] = []
        for entry in sorted {
            if entry.isComment {
                lines.append("# \(entry.commentText)")
            } else {
                let value = try requiredValue(for: entry)
                let formatted = EnvParser.format([(key: entry.key, value: value)])
                lines.append(formatted)
            }
        }
        return lines.joined(separator: "\n")
    }

    func applyRawText(_ text: String, to file: EnvFile, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        let result = EnvParser.parse(text)
        if !result.errors.isEmpty {
            let messages = result.errors.map { "Line \($0.lineNumber): \($0.message)" }
            errorMessage = messages.joined(separator: "\n")
            return false
        }

        let existingEntries = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingSnapshots: [SecretSnapshot]
        do {
            existingSnapshots = try secretSnapshots(for: existingEntries)
        } catch {
            errorMessage = "Failed to prepare changes: \(error.localizedDescription)"
            return false
        }

        let existingByKey: [String: EnvEntry] = {
            var map: [String: EnvEntry] = [:]
            for entry in existingEntries where !entry.isComment {
                if map[entry.key] == nil {
                    map[entry.key] = entry
                }
            }
            return map
        }()

        var usedExistingIds = Set<UUID>()
        var newEntries: [(parsed: ParsedEntry, existing: EnvEntry?)] = []
        var newSecretIdentifiers: [String] = []
        var revealedUpdates: [String: String] = [:]
        var revealedRemovals = Set<String>()

        func fail(_ message: String) -> Bool {
            context.rollback()
            deleteSecretsIfNeeded(for: newSecretIdentifiers)
            restoreSecretsIfNeeded(from: existingSnapshots)
            errorMessage = message
            return false
        }

        for parsed in result.entries {
            if parsed.isComment {
                newEntries.append((parsed, nil))
            } else if let existing = existingByKey[parsed.key], !usedExistingIds.contains(existing.id) {
                usedExistingIds.insert(existing.id)
                newEntries.append((parsed, existing))
            } else {
                newEntries.append((parsed, nil))
            }
        }

        for entry in existingEntries where !usedExistingIds.contains(entry.id) {
            let identifier = entry.keychainIdentifier
            if !entry.isComment {
                do {
                    try keychainService.deleteValue(for: identifier)
                } catch {
                    return fail("Failed to delete removed key: \(error.localizedDescription)")
                }
                if revealedValues[identifier] != nil {
                    revealedRemovals.insert(identifier)
                }
            }
            context.delete(entry)
        }

        for (index, item) in newEntries.enumerated() {
            let parsed = item.parsed
            if let existing = item.existing {
                existing.key = parsed.key
                existing.sortOrder = index
                existing.updatedAt = .now
                do {
                    try keychainService.setValue(parsed.value, for: existing.keychainIdentifier)
                    if revealedValues[existing.keychainIdentifier] != nil {
                        revealedUpdates[existing.keychainIdentifier] = parsed.value
                    }
                } catch {
                    return fail("Failed to update keychain: \(error.localizedDescription)")
                }
            } else {
                let entry = EnvEntry(
                    key: parsed.isComment ? "" : parsed.key,
                    sortOrder: index,
                    isComment: parsed.isComment,
                    comment: parsed.isComment ? parsed.comment : nil
                )
                entry.file = file
                context.insert(entry)
                if !parsed.isComment {
                    do {
                        try keychainService.setValue(parsed.value, for: entry.keychainIdentifier)
                        newSecretIdentifiers.append(entry.keychainIdentifier)
                    } catch {
                        return fail("Failed to save keychain: \(error.localizedDescription)")
                    }
                }
            }
        }

        file.updatedAt = .now
        do {
            try context.save()
            for identifier in revealedRemovals {
                revealedValues.removeValue(forKey: identifier)
            }
            for (identifier, value) in revealedUpdates {
                revealedValues[identifier] = value
            }
            return true
        } catch {
            return fail("Failed to save changes: \(error.localizedDescription)")
        }
    }

    private func secretSnapshots(for entries: [EnvEntry]) throws -> [SecretSnapshot] {
        try entries.filter { !$0.isComment }.map { entry in
            SecretSnapshot(
                identifier: entry.keychainIdentifier,
                value: try keychainService.getValue(for: entry.keychainIdentifier)
            )
        }
    }

    private func deleteSecrets(using snapshots: [SecretSnapshot]) throws {
        for snapshot in snapshots {
            try keychainService.deleteValue(for: snapshot.identifier)
        }
    }

    private func restoreSecretsIfNeeded(from snapshots: [SecretSnapshot]?) {
        guard let snapshots else { return }
        for snapshot in snapshots {
            if let value = snapshot.value {
                try? keychainService.setValue(value, for: snapshot.identifier)
            } else {
                try? keychainService.deleteValue(for: snapshot.identifier)
            }
        }
    }

    private func deleteSecretsIfNeeded(for identifiers: [String]) {
        for identifier in identifiers {
            try? keychainService.deleteValue(for: identifier)
        }
    }

    private func removeRevealedValues(for snapshots: [SecretSnapshot]) {
        for snapshot in snapshots {
            revealedValues.removeValue(forKey: snapshot.identifier)
        }
    }
}
