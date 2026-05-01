import SwiftData
import SwiftUI
import os

@Observable
final class EnvEditorViewModel {
    private(set) var revealedValues: [String: String] = [:]
    var errorMessage: String?
    var lockManager: LockManager?

    @ObservationIgnored
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "EnvEditor")

    init() {}

    private func key(for entry: EnvEntry) -> String { entry.id.uuidString }

    func toggleReveal(for entry: EnvEntry) {
        lockManager?.recordActivity()
        let k = key(for: entry)
        if revealedValues[k] != nil {
            revealedValues.removeValue(forKey: k)
        } else {
            revealedValues[k] = entry.value
        }
    }

    func revealedValue(for entry: EnvEntry) -> String? {
        revealedValues[key(for: entry)]
    }

    func copyValue(for entry: EnvEntry) {
        lockManager?.recordActivity()
        ClipboardManager.shared.copyToClipboard(entry.value)
    }

    func copyKeyValue(for entry: EnvEntry) {
        lockManager?.recordActivity()
        let formatted = EnvParser.format([(key: entry.key, value: entry.value)])
        ClipboardManager.shared.copyToClipboard(formatted)
    }

    func copyKey(for entry: EnvEntry) {
        lockManager?.recordActivity()
        ClipboardManager.shared.copyToClipboard(entry.key)
    }

    @MainActor
    func addEntry(key: String, value: String, to file: EnvFile, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        let sortOrder = ((file.entries ?? []).map(\.sortOrder).max() ?? -1) + 1
        let entry = EnvEntry(key: key, value: value, sortOrder: sortOrder)
        entry.file = file
        context.insert(entry)
        file.updatedAt = .now
        return commit(context: context, failureMessage: "Failed to save entry")
    }

    @MainActor
    func updateEntry(_ entry: EnvEntry, key: String, value: String, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        entry.key = key
        entry.value = value
        entry.updatedAt = .now
        entry.file?.updatedAt = .now
        let revealKey = self.key(for: entry)
        if revealedValues[revealKey] != nil {
            revealedValues[revealKey] = value
        }
        return commit(context: context, failureMessage: "Failed to update entry")
    }

    @MainActor
    func deleteEntry(_ entry: EnvEntry, context: ModelContext) {
        lockManager?.recordActivity()
        errorMessage = nil
        let revealKey = self.key(for: entry)
        entry.file?.updatedAt = .now
        context.delete(entry)
        _ = commit(context: context, failureMessage: "Failed to delete entry")
        revealedValues.removeValue(forKey: revealKey)
    }

    @MainActor
    func deleteFile(_ file: EnvFile, context: ModelContext) throws {
        let removedKeys = (file.entries ?? []).map { key(for: $0) }
        file.project?.updatedAt = .now
        context.delete(file)
        if !commit(context: context, failureMessage: "Failed to delete file") {
            throw NSError(domain: "EnvEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "Failed to delete"])
        }
        for k in removedKeys { revealedValues.removeValue(forKey: k) }
    }

    @MainActor
    func deleteProject(_ project: Project, context: ModelContext) throws {
        let removedKeys = (project.files ?? []).flatMap { $0.entries ?? [] }.map { key(for: $0) }
        context.delete(project)
        if !commit(context: context, failureMessage: "Failed to delete project") {
            throw NSError(domain: "EnvEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "Failed to delete"])
        }
        for k in removedKeys { revealedValues.removeValue(forKey: k) }
    }

    @MainActor
    func moveEntries(in file: EnvFile, from source: IndexSet, to destination: Int, context: ModelContext) {
        var sorted = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in sorted.enumerated() {
            entry.sortOrder = index
        }
        _ = commit(context: context, failureMessage: "Failed to save reorder")
    }

    func duplicateKeys(in file: EnvFile) -> Set<String> {
        let keys = (file.entries ?? []).filter { !$0.isComment }.map(\.key)
        var seen = Set<String>()
        var duplicates = Set<String>()
        for key in keys {
            if seen.contains(key) { duplicates.insert(key) }
            seen.insert(key)
        }
        return duplicates
    }

    func currentValue(for entry: EnvEntry) -> String {
        revealedValues[key(for: entry)] ?? entry.value
    }

    func requiredValue(for entry: EnvEntry) throws -> String {
        entry.value
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
                let formatted = EnvParser.format([(key: entry.key, value: entry.value)])
                lines.append(formatted)
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    func applyRawText(_ text: String, to file: EnvFile, context: ModelContext) -> Bool {
        lockManager?.recordActivity()
        errorMessage = nil
        let result = EnvParser.parse(text)
        if !result.errors.isEmpty {
            errorMessage = result.errors.map { "Line \($0.lineNumber): \($0.message)" }.joined(separator: "\n")
            return false
        }

        let existing = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingByKey: [String: EnvEntry] = {
            var map: [String: EnvEntry] = [:]
            for entry in existing where !entry.isComment {
                if map[entry.key] == nil { map[entry.key] = entry }
            }
            return map
        }()

        var usedIDs = Set<UUID>()
        var ordered: [(parsed: ParsedEntry, existing: EnvEntry?)] = []
        for parsed in result.entries {
            if parsed.isComment {
                ordered.append((parsed, nil))
            } else if let existing = existingByKey[parsed.key], !usedIDs.contains(existing.id) {
                usedIDs.insert(existing.id)
                ordered.append((parsed, existing))
            } else {
                ordered.append((parsed, nil))
            }
        }

        for entry in existing where !usedIDs.contains(entry.id) {
            revealedValues.removeValue(forKey: key(for: entry))
            context.delete(entry)
        }

        for (index, item) in ordered.enumerated() {
            let parsed = item.parsed
            if let existing = item.existing {
                existing.key = parsed.key
                existing.value = parsed.value
                existing.sortOrder = index
                existing.updatedAt = .now
                let k = key(for: existing)
                if revealedValues[k] != nil { revealedValues[k] = parsed.value }
            } else {
                let entry = EnvEntry(
                    key: parsed.isComment ? "" : parsed.key,
                    value: parsed.isComment ? "" : parsed.value,
                    sortOrder: index,
                    isComment: parsed.isComment,
                    comment: parsed.isComment ? parsed.comment : nil
                )
                entry.file = file
                context.insert(entry)
            }
        }

        file.updatedAt = .now
        return commit(context: context, failureMessage: "Failed to save changes")
    }

    @MainActor
    private func commit(context: ModelContext, failureMessage: String) -> Bool {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "\(failureMessage): \(error.localizedDescription)"
            return false
        }
        do {
            try VaultRepository.shared.captureFromSwiftData(context: context)
            return true
        } catch {
            context.rollback()
            errorMessage = "\(failureMessage): \(error.localizedDescription)"
            return false
        }
    }
}
