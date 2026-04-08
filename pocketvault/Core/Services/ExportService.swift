import SwiftData
import Foundation

enum ExportService {
    private static func secretValue(
        for entry: EnvEntry,
        keychainService: KeychainServiceProtocol
    ) throws -> String {
        guard let value = try keychainService.getValue(for: entry.keychainIdentifier) else {
            throw VaultError.missingSecret(entry.key)
        }
        return value
    }

    static func exportFile(
        _ file: EnvFile,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) throws -> String {
        let sortedEntries = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var lines: [String] = []

        for entry in sortedEntries {
            if entry.isComment {
                lines.append("# \(entry.commentText)")
                continue
            }
            let value = try secretValue(for: entry, keychainService: keychainService)
            lines.append(EnvParser.format([(key: entry.key, value: value)]))
        }

        return lines.joined(separator: "\n")
    }

    static func exportProject(
        _ project: Project,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) throws -> [(fileName: String, content: String)] {
        try (project.files ?? [])
            .sorted { $0.name < $1.name }
            .map { file in
                let content = try exportFile(file, keychainService: keychainService)
                return (fileName: file.name, content: content)
            }
    }

    static func copyAllEntries(
        _ file: EnvFile,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) throws -> String {
        try exportFile(file, keychainService: keychainService)
    }
}
