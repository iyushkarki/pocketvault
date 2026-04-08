import SwiftData
import Foundation

enum ImportConflictResolution {
    case skip
    case overwrite
    case rename
}

struct ImportResult {
    let imported: Int
    let skipped: Int
    let errors: [String]
}

enum ImportService {
    static func importEntries(
        _ parsedEntries: [ParsedEntry],
        into file: EnvFile,
        conflictResolution: ImportConflictResolution,
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        context: ModelContext
    ) throws -> ImportResult {
        var existingKeys = Set((file.entries ?? []).filter { !$0.isComment }.map(\.key))
        let maxSortOrder = (file.entries ?? []).map(\.sortOrder).max() ?? -1
        var nextSortOrder = maxSortOrder + 1
        var imported = 0
        var skipped = 0
        var errors: [String] = []
        var seenInBatch = Set<String>()
        var createdIdentifiers: [String] = []
        var updatedSnapshots: [(identifier: String, originalValue: String?)] = []

        func snapshotIfNeeded(for identifier: String) {
            guard !updatedSnapshots.contains(where: { $0.identifier == identifier }) else { return }
            let originalValue = try? keychainService.getValue(for: identifier)
            updatedSnapshots.append((identifier: identifier, originalValue: originalValue))
        }

        for parsed in parsedEntries {
            if parsed.isComment {
                let entry = EnvEntry(key: "", sortOrder: nextSortOrder, isComment: true, comment: parsed.comment)
                entry.file = file
                context.insert(entry)
                nextSortOrder += 1
                imported += 1
                continue
            }

            if seenInBatch.contains(parsed.key) {
                skipped += 1
                continue
            }
            seenInBatch.insert(parsed.key)

            let isConflict = existingKeys.contains(parsed.key)

            if isConflict {
                switch conflictResolution {
                case .skip:
                    skipped += 1
                    continue
                case .overwrite:
                    if let existing = (file.entries ?? []).first(where: { $0.key == parsed.key }) {
                        do {
                            snapshotIfNeeded(for: existing.keychainIdentifier)
                            try keychainService.setValue(parsed.value, for: existing.keychainIdentifier)
                            existing.updatedAt = .now
                            imported += 1
                        } catch {
                            errors.append("Failed to update \(parsed.key): \(error.localizedDescription)")
                        }
                    }
                    continue
                case .rename:
                    let renamedKey = generateUniqueKey(parsed.key, existingKeys: existingKeys)
                    let entry = EnvEntry(key: renamedKey, sortOrder: nextSortOrder)
                    entry.file = file
                    context.insert(entry)
                    do {
                        try keychainService.setValue(parsed.value, for: entry.keychainIdentifier)
                        createdIdentifiers.append(entry.keychainIdentifier)
                        existingKeys.insert(renamedKey)
                        nextSortOrder += 1
                        imported += 1
                    } catch {
                        context.delete(entry)
                        errors.append("Failed to save \(renamedKey): \(error.localizedDescription)")
                    }
                    continue
                }
            }

            let entry = EnvEntry(key: parsed.key, sortOrder: nextSortOrder)
            entry.file = file
            context.insert(entry)
            do {
                try keychainService.setValue(parsed.value, for: entry.keychainIdentifier)
                createdIdentifiers.append(entry.keychainIdentifier)
                existingKeys.insert(parsed.key)
                nextSortOrder += 1
                imported += 1
            } catch {
                context.delete(entry)
                errors.append("Failed to save \(parsed.key): \(error.localizedDescription)")
            }
        }

        file.updatedAt = .now
        do {
            try context.save()
            return ImportResult(imported: imported, skipped: skipped, errors: errors)
        } catch {
            context.rollback()
            for identifier in createdIdentifiers {
                try? keychainService.deleteValue(for: identifier)
            }
            for snapshot in updatedSnapshots {
                if let originalValue = snapshot.originalValue {
                    try? keychainService.setValue(originalValue, for: snapshot.identifier)
                } else {
                    try? keychainService.deleteValue(for: snapshot.identifier)
                }
            }
            throw error
        }
    }

    private static func generateUniqueKey(_ key: String, existingKeys: Set<String>) -> String {
        var suffix = 2
        var candidate = "\(key)_\(suffix)"
        while existingKeys.contains(candidate) {
            suffix += 1
            candidate = "\(key)_\(suffix)"
        }
        return candidate
    }
}
