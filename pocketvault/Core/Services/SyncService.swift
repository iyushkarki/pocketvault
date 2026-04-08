import Foundation
import SwiftData
import CloudKit
import os

enum SyncStatus: Equatable {
    case disabled
    case unavailable(String)
    case migrating
    case synced
    case error(String)
}

@Observable
final class SyncService {
    private(set) var status: SyncStatus = .disabled
    private(set) var requiresRestart = false
    private(set) var conflictCount = 0

    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "SyncService")

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
    }

    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func checkStatus() {
        if !isEnabled {
            status = .disabled
            return
        }

        if !iCloudAvailable {
            status = .unavailable("Not signed into iCloud")
            return
        }

        status = .synced
    }

    func enableSync() async throws {
        guard iCloudAvailable else {
            status = .unavailable("Not signed into iCloud")
            throw SyncError.iCloudUnavailable
        }

        status = .migrating
        Self.logger.info("Enabling iCloud sync...")

        do {
            let count = try KeychainService.shared.migrateToSyncable()
            Self.logger.info("Migrated \(count) Keychain items to syncable")
        } catch {
            status = .error("Keychain migration failed")
            Self.logger.error("Keychain migration failed: \(error.localizedDescription)")
            throw error
        }

        UserDefaults.standard.set(true, forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
        requiresRestart = true
        status = .synced
        Self.logger.info("iCloud sync enabled — app restart required for CloudKit")
    }

    func disableSync() async throws {
        status = .migrating
        Self.logger.info("Disabling iCloud sync...")

        do {
            let count = try KeychainService.shared.migrateToLocalOnly()
            Self.logger.info("Reverted \(count) Keychain items to local-only")
        } catch {
            status = .error("Keychain revert failed")
            Self.logger.error("Keychain revert failed: \(error.localizedDescription)")
            throw error
        }

        UserDefaults.standard.set(false, forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
        requiresRestart = true
        status = .disabled
        Self.logger.info("iCloud sync disabled — app restart required for CloudKit")
    }

    // MARK: - Conflict Resolution

    @discardableResult
    func resolveDuplicates(in context: ModelContext) throws -> Int {
        var resolved = 0
        resolved += try resolveDuplicateProjects(in: context)
        resolved += try resolveDuplicateEntries(in: context)
        if resolved > 0 {
            try context.save()
            Self.logger.info("Resolved \(resolved) sync conflicts")
        }
        conflictCount = resolved
        return resolved
    }

    private func resolveDuplicateProjects(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)])
        let projects = try context.fetch(descriptor)

        var seen: [String: Project] = [:]
        var resolved = 0

        for project in projects {
            if seen[project.name] != nil {
                let timestamp = Int(project.createdAt.timeIntervalSince1970)
                project.name = "\(project.name)_conflict_\(timestamp)"
                resolved += 1
                Self.logger.info("Renamed duplicate project to: \(project.name)")
            } else {
                seen[project.name] = project
            }
        }

        return resolved
    }

    private func resolveDuplicateEntries(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<EnvFile>()
        let files = try context.fetch(descriptor)

        var resolved = 0

        for file in files {
            let entries = (file.entries ?? []).sorted { $0.createdAt < $1.createdAt }
            var seenKeys: [String: EnvEntry] = [:]

            for entry in entries where !entry.isComment {
                if seenKeys[entry.key] != nil {
                    let timestamp = Int(entry.createdAt.timeIntervalSince1970)
                    entry.key = "\(entry.key)_conflict_\(timestamp)"
                    resolved += 1
                    Self.logger.info("Renamed duplicate entry to: \(entry.key)")
                } else {
                    seenKeys[entry.key] = entry
                }
            }
        }

        return resolved
    }
}

enum SyncError: LocalizedError {
    case iCloudUnavailable
    case migrationFailed

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "iCloud is not available. Sign into iCloud in System Settings."
        case .migrationFailed: return "Failed to migrate Keychain items."
        }
    }
}
