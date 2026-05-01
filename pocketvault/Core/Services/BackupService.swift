import Foundation

enum BackupServiceError: LocalizedError {
    case noData
    case serializationFailed
    case deserializationFailed
    case versionUnsupported(Int)

    var errorDescription: String? {
        switch self {
        case .noData: return "Vault has no data to back up."
        case .serializationFailed: return "Failed to serialize the backup."
        case .deserializationFailed: return "Failed to read the backup file."
        case .versionUnsupported(let v): return "Unsupported backup version (\(v))."
        }
    }
}

enum BackupService {
    static let currentVersion = 2

    static func makeBackup(from snapshot: VaultSnapshot) throws -> Data {
        guard snapshot.hasData else { throw BackupServiceError.noData }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            return try encoder.encode(snapshot)
        } catch {
            throw BackupServiceError.serializationFailed
        }
    }

    static func parseBackup(_ data: Data) throws -> VaultSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snapshot = try decoder.decode(VaultSnapshot.self, from: data)
            guard snapshot.version <= currentVersion else {
                throw BackupServiceError.versionUnsupported(snapshot.version)
            }
            return snapshot
        } catch let e as BackupServiceError {
            throw e
        } catch {
            throw BackupServiceError.deserializationFailed
        }
    }

    static func mergeIntoCurrent(_ incoming: VaultSnapshot, current: VaultSnapshot) -> VaultSnapshot {
        var merged = current

        var existingProjectsByName: [String: Int] = [:]
        for (idx, project) in merged.projects.enumerated() {
            existingProjectsByName[project.name.lowercased()] = idx
        }

        for incomingProject in incoming.projects {
            let uniqueName = uniqueProjectName(incomingProject.name, existing: merged.projects)
            var newProject = incomingProject
            newProject.id = UUID()
            newProject.name = uniqueName
            newProject.files = newProject.files.map { file in
                var f = file
                f.id = UUID()
                f.entries = f.entries.map { entry in
                    var e = entry
                    e.id = UUID()
                    return e
                }
                return f
            }
            merged.projects.append(newProject)
        }

        merged.revision = UUID().uuidString
        merged.updatedAt = .now
        merged.updatedByDeviceID = VaultRepository.deviceID()
        merged.updatedByDeviceName = VaultRepository.deviceName()
        return merged
    }

    private static func uniqueProjectName(_ proposed: String, existing: [VaultSnapshot.Project]) -> String {
        let names = Set(existing.map { $0.name.lowercased() })
        if !names.contains(proposed.lowercased()) { return proposed }
        var counter = 2
        while names.contains("\(proposed) (\(counter))".lowercased()) {
            counter += 1
        }
        return "\(proposed) (\(counter))"
    }
}
