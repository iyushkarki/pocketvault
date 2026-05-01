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
    @MainActor
    static func importEntries(
        _ parsedEntries: [ParsedEntry],
        into file: EnvFile,
        conflictResolution: ImportConflictResolution,
        context: ModelContext
    ) throws -> ImportResult {
        var existingKeys = Set((file.entries ?? []).filter { !$0.isComment }.map(\.key))
        let maxSortOrder = (file.entries ?? []).map(\.sortOrder).max() ?? -1
        var nextSortOrder = maxSortOrder + 1
        var imported = 0
        var skipped = 0
        let errors: [String] = []
        var seenInBatch = Set<String>()

        for parsed in parsedEntries {
            if parsed.isComment {
                let entry = EnvEntry(key: "", value: "", sortOrder: nextSortOrder, isComment: true, comment: parsed.comment)
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
                        existing.value = parsed.value
                        existing.updatedAt = .now
                        imported += 1
                    }
                    continue
                case .rename:
                    let renamedKey = generateUniqueKey(parsed.key, existingKeys: existingKeys)
                    let entry = EnvEntry(key: renamedKey, value: parsed.value, sortOrder: nextSortOrder)
                    entry.file = file
                    context.insert(entry)
                    existingKeys.insert(renamedKey)
                    nextSortOrder += 1
                    imported += 1
                    continue
                }
            }

            let entry = EnvEntry(key: parsed.key, value: parsed.value, sortOrder: nextSortOrder)
            entry.file = file
            context.insert(entry)
            existingKeys.insert(parsed.key)
            nextSortOrder += 1
            imported += 1
        }

        file.updatedAt = .now
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        do {
            try VaultRepository.shared.captureFromSwiftData(context: context)
            return ImportResult(imported: imported, skipped: skipped, errors: errors)
        } catch {
            context.rollback()
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
