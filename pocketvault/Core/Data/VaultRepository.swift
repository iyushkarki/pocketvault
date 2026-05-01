import Foundation
import SwiftData
import SystemConfiguration
import os

@MainActor
@Observable
final class VaultRepository {
    static let shared = VaultRepository()

    private(set) var snapshot: VaultSnapshot
    private(set) var lastError: Error?

    var onSnapshotChanged: (@MainActor (VaultSnapshot) -> Void)?

    @ObservationIgnored
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "VaultRepository")
    @ObservationIgnored
    private weak var modelContainer: ModelContainer?
    @ObservationIgnored
    private var didHydrateForContainer: ObjectIdentifier?

    private init() {
        self.snapshot = VaultSnapshot.empty(
            deviceID: VaultRepository.deviceID(),
            deviceName: VaultRepository.deviceName()
        )
    }

    func bootstrap(container: ModelContainer) throws {
        self.modelContainer = container
        if let loaded = try EncryptedVaultStore.shared.load(syncableKey: false) {
            self.snapshot = loaded
        }

        let containerID = ObjectIdentifier(container)
        if didHydrateForContainer == containerID {
            return
        }
        try hydrateSwiftData(context: container.mainContext)
        didHydrateForContainer = containerID
    }

    func replaceSnapshot(_ newSnapshot: VaultSnapshot, persist: Bool = true, emitChange: Bool = true) throws {
        snapshot = newSnapshot
        if persist {
            try EncryptedVaultStore.shared.save(newSnapshot, syncableKey: false)
        }
        if let modelContainer {
            try hydrateSwiftData(context: modelContainer.mainContext)
        }
        if emitChange {
            onSnapshotChanged?(newSnapshot)
        }
    }

    func captureFromSwiftData(context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<Project>())
        var newSnapshot = makeSnapshot(from: projects)

        if newSnapshot.projects == snapshot.projects {
            return
        }

        newSnapshot.revision = UUID().uuidString
        newSnapshot.updatedAt = .now
        newSnapshot.updatedByDeviceID = VaultRepository.deviceID()
        newSnapshot.updatedByDeviceName = VaultRepository.deviceName()

        try EncryptedVaultStore.shared.save(newSnapshot, syncableKey: false)
        snapshot = newSnapshot
        onSnapshotChanged?(newSnapshot)
    }

    func hydrateSwiftData(context: ModelContext) throws {
        let existingProjects = try context.fetch(FetchDescriptor<Project>())
        var existingProjectsByID = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.id, $0) })

        let snapshotProjectIDs = Set(snapshot.projects.map(\.id))

        for project in existingProjects where !snapshotProjectIDs.contains(project.id) {
            context.delete(project)
            existingProjectsByID.removeValue(forKey: project.id)
        }

        for projectSnapshot in snapshot.projects {
            let project: Project
            if let existing = existingProjectsByID[projectSnapshot.id] {
                project = existing
                project.name = projectSnapshot.name
                project.projectDescription = projectSnapshot.description
                project.createdAt = projectSnapshot.createdAt
                project.updatedAt = projectSnapshot.updatedAt
            } else {
                project = Project(name: projectSnapshot.name, description: projectSnapshot.description)
                project.id = projectSnapshot.id
                project.createdAt = projectSnapshot.createdAt
                project.updatedAt = projectSnapshot.updatedAt
                context.insert(project)
            }

            let existingFiles = project.files ?? []
            var existingFilesByID = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0.id, $0) })
            let snapshotFileIDs = Set(projectSnapshot.files.map(\.id))

            for file in existingFiles where !snapshotFileIDs.contains(file.id) {
                context.delete(file)
                existingFilesByID.removeValue(forKey: file.id)
            }

            for fileSnapshot in projectSnapshot.files {
                let file: EnvFile
                if let existing = existingFilesByID[fileSnapshot.id] {
                    file = existing
                    file.name = fileSnapshot.name
                    file.createdAt = fileSnapshot.createdAt
                    file.updatedAt = fileSnapshot.updatedAt
                    file.project = project
                } else {
                    file = EnvFile(name: fileSnapshot.name)
                    file.id = fileSnapshot.id
                    file.createdAt = fileSnapshot.createdAt
                    file.updatedAt = fileSnapshot.updatedAt
                    file.project = project
                    context.insert(file)
                }

                let existingEntries = file.entries ?? []
                var existingEntriesByID = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.id, $0) })
                let snapshotEntryIDs = Set(fileSnapshot.entries.map(\.id))

                for entry in existingEntries where !snapshotEntryIDs.contains(entry.id) {
                    context.delete(entry)
                    existingEntriesByID.removeValue(forKey: entry.id)
                }

                for entrySnapshot in fileSnapshot.entries {
                    if let existing = existingEntriesByID[entrySnapshot.id] {
                        existing.key = entrySnapshot.key
                        existing.value = entrySnapshot.value
                        existing.sortOrder = entrySnapshot.sortOrder
                        existing.isComment = entrySnapshot.isComment
                        existing.comment = entrySnapshot.comment
                        existing.createdAt = entrySnapshot.createdAt
                        existing.updatedAt = entrySnapshot.updatedAt
                        existing.file = file
                    } else {
                        let entry = EnvEntry(
                            key: entrySnapshot.key,
                            value: entrySnapshot.value,
                            sortOrder: entrySnapshot.sortOrder,
                            isComment: entrySnapshot.isComment,
                            comment: entrySnapshot.comment
                        )
                        entry.id = entrySnapshot.id
                        entry.createdAt = entrySnapshot.createdAt
                        entry.updatedAt = entrySnapshot.updatedAt
                        entry.file = file
                        context.insert(entry)
                    }
                }
            }
        }

        try context.save()
    }

    func wipeLocalDataKeepingCloudKey(emitChange: Bool = true) throws {
        try EncryptedVaultStore.shared.deleteLocalVault()
        try VaultKeyService.shared.deleteLocalKey()
        snapshot = VaultSnapshot.empty(
            deviceID: VaultRepository.deviceID(),
            deviceName: VaultRepository.deviceName()
        )
        if let modelContainer {
            try hydrateSwiftData(context: modelContainer.mainContext)
        }
        if emitChange {
            onSnapshotChanged?(snapshot)
        }
    }

    func wipeEverything(emitChange: Bool = true) throws {
        try EncryptedVaultStore.shared.deleteLocalVault()
        try VaultKeyService.shared.deleteAllKeys()
        snapshot = VaultSnapshot.empty(
            deviceID: VaultRepository.deviceID(),
            deviceName: VaultRepository.deviceName()
        )
        if let modelContainer {
            try hydrateSwiftData(context: modelContainer.mainContext)
        }
        if emitChange {
            onSnapshotChanged?(snapshot)
        }
    }

    private func makeSnapshot(from projects: [Project]) -> VaultSnapshot {
        let sortedProjects = projects.sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.createdAt < rhs.createdAt
        }

        let snapshotProjects: [VaultSnapshot.Project] = sortedProjects.map { project in
            let files = (project.files ?? [])
                .sorted { lhs, rhs in
                    if lhs.name != rhs.name { return lhs.name < rhs.name }
                    return lhs.createdAt < rhs.createdAt
                }
                .map { file in
                    let entries = (file.entries ?? [])
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { entry in
                            VaultSnapshot.Entry(
                                id: entry.id,
                                key: entry.key,
                                value: entry.isComment ? "" : entry.value,
                                sortOrder: entry.sortOrder,
                                isComment: entry.isComment,
                                comment: entry.comment,
                                createdAt: entry.createdAt,
                                updatedAt: entry.updatedAt
                            )
                        }
                    return VaultSnapshot.File(
                        id: file.id,
                        name: file.name,
                        createdAt: file.createdAt,
                        updatedAt: file.updatedAt,
                        entries: entries
                    )
                }
            return VaultSnapshot.Project(
                id: project.id,
                name: project.name,
                description: project.projectDescription,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
                files: files
            )
        }

        return VaultSnapshot(
            version: snapshot.version,
            revision: snapshot.revision,
            updatedAt: snapshot.updatedAt,
            updatedByDeviceID: snapshot.updatedByDeviceID,
            updatedByDeviceName: snapshot.updatedByDeviceName,
            projects: snapshotProjects
        )
    }

    static func deviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: AppConfig.UserDefaultsKey.deviceIdentity) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: AppConfig.UserDefaultsKey.deviceIdentity)
        return newID
    }

    static func deviceName() -> String {
        if let copied = SCDynamicStoreCopyComputerName(nil, nil) as String?,
           !copied.isEmpty {
            return copied
        }
        let host = Host.current().localizedName ?? ""
        if !host.isEmpty { return host }
        let processHost = ProcessInfo.processInfo.hostName
        if !processHost.isEmpty { return processHost }
        return "This Mac"
    }
}
