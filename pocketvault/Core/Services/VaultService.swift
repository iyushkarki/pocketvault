import Foundation
import SwiftData

enum VaultError: LocalizedError {
    case noProjects
    case serializationFailed
    case deserializationFailed
    case missingSecret(String)
    case secretReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProjects: return "No projects to export."
        case .serializationFailed: return "Failed to serialize vault data."
        case .deserializationFailed: return "Failed to read vault data."
        case .missingSecret(let key): return "Missing stored value for \(key)."
        case .secretReadFailed(let key): return "Failed to read the stored value for \(key)."
        }
    }
}

struct VaultData: Codable {
    let version: Int
    let exportedAt: Date
    let projects: [VaultProject]

    struct VaultProject: Codable {
        let name: String
        let description: String?
        let files: [VaultFile]
    }

    struct VaultFile: Codable {
        let name: String
        let entries: [VaultEntry]
    }

    struct VaultEntry: Codable {
        let key: String
        let value: String
        let sortOrder: Int
        let isComment: Bool
        let comment: String?
    }
}

enum VaultService {
    static func exportAll(
        projects: [Project],
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) throws -> VaultData {
        guard !projects.isEmpty else { throw VaultError.noProjects }

        let vaultProjects = try projects
            .sorted(by: { $0.name < $1.name })
            .map { project in
                let files = try (project.files ?? [])
                    .sorted(by: { $0.name < $1.name })
                    .map { file in
                        let entries = try (file.entries ?? [])
                            .sorted(by: { $0.sortOrder < $1.sortOrder })
                            .map { entry in
                                let value: String
                                if entry.isComment {
                                    value = ""
                                } else {
                                    do {
                                        guard let storedValue = try keychainService.getValue(for: entry.keychainIdentifier) else {
                                            throw VaultError.missingSecret(entry.key)
                                        }
                                        value = storedValue
                                    } catch let error as VaultError {
                                        throw error
                                    } catch {
                                        throw VaultError.secretReadFailed(entry.key)
                                    }
                                }
                                return VaultData.VaultEntry(
                                    key: entry.isComment ? "" : entry.key,
                                    value: value,
                                    sortOrder: entry.sortOrder,
                                    isComment: entry.isComment,
                                    comment: entry.isComment ? entry.commentText : entry.comment
                                )
                            }
                        return VaultData.VaultFile(name: file.name, entries: entries)
                    }
                return VaultData.VaultProject(
                    name: project.name,
                    description: project.projectDescription,
                    files: files
                )
            }

        return VaultData(version: 1, exportedAt: .now, projects: vaultProjects)
    }

    static func serialize(_ data: VaultData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(data) else {
            throw VaultError.serializationFailed
        }
        return json
    }

    static func deserialize(_ data: Data) throws -> VaultData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let vault = try? decoder.decode(VaultData.self, from: data) else {
            throw VaultError.deserializationFailed
        }
        return vault
    }

    static func importVault(
        _ vault: VaultData,
        context: ModelContext,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) throws -> (projects: Int, files: Int, entries: Int) {
        var projectCount = 0
        var fileCount = 0
        var entryCount = 0
        var createdIdentifiers: [String] = []

        do {
            for vaultProject in vault.projects {
                let project = Project(name: vaultProject.name, description: vaultProject.description)
                context.insert(project)
                projectCount += 1

                for vaultFile in vaultProject.files {
                    let file = EnvFile(name: vaultFile.name)
                    file.project = project
                    context.insert(file)
                    fileCount += 1

                    for vaultEntry in vaultFile.entries {
                        let entry = EnvEntry(
                            key: vaultEntry.isComment ? "" : vaultEntry.key,
                            sortOrder: vaultEntry.sortOrder,
                            isComment: vaultEntry.isComment,
                            comment: vaultEntry.isComment ? (vaultEntry.comment ?? vaultEntry.key) : vaultEntry.comment
                        )
                        entry.file = file
                        context.insert(entry)

                        if !vaultEntry.isComment {
                            try keychainService.setValue(vaultEntry.value, for: entry.keychainIdentifier)
                            createdIdentifiers.append(entry.keychainIdentifier)
                        }
                        entryCount += 1
                    }
                }
            }

            try context.save()
            return (projects: projectCount, files: fileCount, entries: entryCount)
        } catch {
            context.rollback()
            for identifier in createdIdentifiers {
                try? keychainService.deleteValue(for: identifier)
            }
            throw error
        }
    }
}
