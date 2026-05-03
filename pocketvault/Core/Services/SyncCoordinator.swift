import Foundation
import SwiftData
import CloudKit
import os

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable {
        case off
        case ready
        case syncing
        case conflict(local: VaultSnapshot, remote: VaultSnapshot)
        case remoteDeleted(revision: String, remoteUpdatedAt: Date, remoteUpdatedByDeviceName: String)
        case needsAttention(IssueKind)
    }

    enum IssueKind: Equatable {
        case iCloudKeychainUnavailable(reason: String)
        case cloudKitAccountUnavailable(message: String)
        case remoteUnreadable
        case syncError(message: String)
    }

    private(set) var state: State = .off
    private(set) var isEnabled: Bool
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: Error?

    @ObservationIgnored
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "SyncCoordinator")
    @ObservationIgnored
    private weak var modelContainer: ModelContainer?
    @ObservationIgnored
    private var pendingUploadTask: Task<Void, Never>?
    @ObservationIgnored
    private var pendingRefresh: Bool = false
    @ObservationIgnored
    private static let lastSyncedRevisionKey = AppConfig.UserDefaultsKey.lastSyncedRevision
    @ObservationIgnored
    private static let acknowledgedDeletedRemoteRevisionKey = AppConfig.UserDefaultsKey.acknowledgedDeletedRemoteRevision

    static let shared = SyncCoordinator()

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
    }

    var lastSyncedRevision: String? {
        get { UserDefaults.standard.string(forKey: Self.lastSyncedRevisionKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.lastSyncedRevisionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncedRevisionKey)
            }
        }
    }

    private var acknowledgedDeletedRemoteRevision: String? {
        get { UserDefaults.standard.string(forKey: Self.acknowledgedDeletedRemoteRevisionKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.acknowledgedDeletedRemoteRevisionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.acknowledgedDeletedRemoteRevisionKey)
            }
        }
    }

    private func setSyncEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
    }

    func bootstrap(container: ModelContainer) {
        self.modelContainer = container

        VaultRepository.shared.onSnapshotChanged = { [weak self] snapshot in
            self?.scheduleUpload(for: snapshot)
        }

        CloudVaultSubscription.shared.onManifestChanged = { [weak self] in
            self?.refresh()
        }

        if isEnabled {
            Task { await startSync() }
        } else {
            state = .off
        }
    }

    func startSync() async {
        let status = await Task.detached { ICloudKeychainAvailability.check() }.value
        switch status {
        case .unavailable(let reason):
            state = .needsAttention(.iCloudKeychainUnavailable(reason: reason))
            return
        case .available, .unknown:
            break
        }

        setSyncEnabled(true)
        state = .syncing

        do {
            let manifest = try await CloudVaultStore.shared.fetchManifest()
            if let manifest, !manifest.isDeleted {
                guard try VaultKeyService.shared.readKey(syncable: true) != nil else {
                    state = .needsAttention(.syncError(message: CloudVaultStoreError.syncKeyUnavailable.localizedDescription))
                    return
                }
            } else if manifest == nil, VaultRepository.shared.snapshot.hasData {
                _ = try VaultKeyService.shared.ensureSyncableReplicaFromLocalKey()
            }
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            state = .needsAttention(.cloudKitAccountUnavailable(message: ckError.localizedDescription))
            return
        } catch {
            lastError = error
            logger.error("startSync failed: \(error.localizedDescription)")
            state = .needsAttention(.syncError(message: error.localizedDescription))
            return
        }

        state = .ready
        CloudVaultSubscription.shared.start()
        refresh()
    }

    func stopSync() {
        setSyncEnabled(false)
        CloudVaultSubscription.shared.stop()
        pendingUploadTask?.cancel()
        pendingUploadTask = nil
        pendingRefresh = false
        state = .off
    }

    func refresh() {
        guard isEnabled else { return }
        switch state {
        case .needsAttention, .conflict, .remoteDeleted:
            return
        case .syncing:
            pendingRefresh = true
            return
        case .off, .ready:
            performRefresh()
        }
    }

    private func performRefresh() {
        Task {
            await self.syncOnce()
            if self.pendingRefresh {
                self.pendingRefresh = false
                self.performRefresh()
            }
        }
    }

    func syncOnce() async {
        guard isEnabled else { return }
        state = .syncing

        do {
            guard let manifest = try await CloudVaultStore.shared.fetchManifest() else {
                try await pushIfNeeded()
                state = .ready
                lastSyncedAt = .now
                return
            }

            let local = VaultRepository.shared.snapshot

            if manifest.isDeleted {
                if local.hasData && acknowledgedDeletedRemoteRevision == manifest.revision {
                    try await saveLocalSnapshot(local)
                } else {
                    handleDeletedManifest(manifest)
                }
                return
            }

            acknowledgedDeletedRemoteRevision = nil
            let knownRevision = lastSyncedRevision

            if manifest.revision == local.revision {
                state = .ready
                lastSyncedAt = .now
                lastSyncedRevision = local.revision
                return
            }

            if knownRevision == nil || knownRevision == local.revision {
                guard let remoteSnapshot = try await CloudVaultStore.shared.fetchSnapshot() else {
                    try await pushIfNeeded()
                    state = .ready
                    lastSyncedAt = .now
                    return
                }
                if knownRevision == nil && local.hasData && remoteSnapshot.hasData {
                    state = .conflict(local: local, remote: remoteSnapshot)
                    return
                }
                try VaultRepository.shared.replaceSnapshot(remoteSnapshot, persist: true, emitChange: false)
                lastSyncedRevision = remoteSnapshot.revision
                state = .ready
                lastSyncedAt = .now
                return
            }

            if knownRevision == manifest.revision {
                try await saveLocalSnapshot(local)
                return
            }

            guard let remoteSnapshot = try await CloudVaultStore.shared.fetchSnapshot() else {
                state = .ready
                return
            }
            state = .conflict(local: local, remote: remoteSnapshot)
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            state = .needsAttention(.cloudKitAccountUnavailable(message: ckError.localizedDescription))
        } catch CloudVaultStoreError.cloudPayloadUnreadable {
            logger.error("Cloud payload unreadable on this Mac")
            state = .needsAttention(.remoteUnreadable)
        } catch {
            lastError = error
            logger.error("syncOnce failed: \(error.localizedDescription)")
            state = .needsAttention(.syncError(message: error.localizedDescription))
        }
    }

    private func pushIfNeeded() async throws {
        let snapshot = VaultRepository.shared.snapshot
        guard snapshot.hasData else { return }
        try await saveLocalSnapshot(snapshot)
    }

    private func scheduleUpload(for snapshot: VaultSnapshot) {
        guard isEnabled else { return }
        switch state {
        case .needsAttention, .conflict, .remoteDeleted:
            return
        case .off, .ready, .syncing:
            break
        }
        pendingUploadTask?.cancel()
        pendingUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.uploadCurrent()
        }
    }

    private func uploadCurrent() async {
        guard isEnabled else { return }
        switch state {
        case .needsAttention, .conflict, .remoteDeleted:
            return
        case .off, .ready, .syncing:
            break
        }
        state = .syncing
        do {
            let snapshot = VaultRepository.shared.snapshot
            if let manifest = try await CloudVaultStore.shared.fetchManifest() {
                if manifest.isDeleted {
                    if snapshot.hasData && acknowledgedDeletedRemoteRevision == manifest.revision {
                        try await saveLocalSnapshot(snapshot)
                    } else {
                        handleDeletedManifest(manifest)
                    }
                    return
                }

                acknowledgedDeletedRemoteRevision = nil

                guard snapshot.hasData else {
                    state = .ready
                    return
                }

                if manifest.revision != snapshot.revision && manifest.revision != lastSyncedRevision {
                    guard let remoteSnapshot = try await CloudVaultStore.shared.fetchSnapshot() else {
                        state = .ready
                        return
                    }
                    state = .conflict(local: snapshot, remote: remoteSnapshot)
                    return
                }
            }

            try await saveLocalSnapshot(snapshot)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            await syncOnce()
        } catch CloudVaultStoreError.cloudPayloadUnreadable {
            logger.error("Cloud payload unreadable on this Mac")
            state = .needsAttention(.remoteUnreadable)
        } catch CloudVaultStoreError.syncKeyUnavailable {
            logger.error("Cloud payload key unavailable on this Mac")
            state = .needsAttention(.remoteUnreadable)
        } catch {
            lastError = error
            logger.error("uploadCurrent failed: \(error.localizedDescription)")
            state = .needsAttention(.syncError(message: error.localizedDescription))
        }
        if pendingRefresh {
            pendingRefresh = false
            performRefresh()
        }
    }

    func resolveConflict(useLocal: Bool) async {
        guard case .conflict(let local, let remote) = state else { return }
        state = .syncing
        do {
            if useLocal {
                var promoted = local
                promoted.revision = UUID().uuidString
                promoted.updatedAt = .now
                promoted.updatedByDeviceID = VaultRepository.deviceID()
                promoted.updatedByDeviceName = VaultRepository.deviceName()
                try VaultRepository.shared.replaceSnapshot(promoted, persist: true, emitChange: false)
                try await saveLocalSnapshot(promoted)
            } else {
                try VaultRepository.shared.replaceSnapshot(remote, persist: true, emitChange: false)
                lastSyncedRevision = remote.revision
            }
            lastSyncedAt = .now
            state = .ready
        } catch {
            lastError = error
            state = .needsAttention(.syncError(message: error.localizedDescription))
        }
    }

    func resolveRemoteDeleted(keepLocal: Bool) async {
        guard case .remoteDeleted(let deletedRevision, _, _) = state else { return }
        state = .syncing
        do {
            if keepLocal {
                let local = VaultRepository.shared.snapshot
                var promoted = local
                promoted.revision = UUID().uuidString
                promoted.updatedAt = .now
                promoted.updatedByDeviceID = VaultRepository.deviceID()
                promoted.updatedByDeviceName = VaultRepository.deviceName()
                try VaultRepository.shared.replaceSnapshot(promoted, persist: true, emitChange: false)
                try await saveLocalSnapshot(promoted)
            } else {
                try VaultRepository.shared.wipeEverything(emitChange: false)
                lastSyncedRevision = nil
                acknowledgedDeletedRemoteRevision = deletedRevision
            }
            lastSyncedAt = .now
            state = .ready
        } catch {
            lastError = error
            state = .needsAttention(.syncError(message: error.localizedDescription))
        }
    }

    func overwriteRemoteWithLocal() async {
        state = .syncing
        do {
            _ = try VaultKeyService.shared.ensureSyncableReplicaFromLocalKey()
            try await CloudVaultStore.shared.deleteRemoteVault(
                deviceID: VaultRepository.deviceID(),
                deviceName: VaultRepository.deviceName()
            )
            var snapshot = VaultRepository.shared.snapshot
            snapshot.revision = UUID().uuidString
            snapshot.updatedAt = .now
            snapshot.updatedByDeviceID = VaultRepository.deviceID()
            snapshot.updatedByDeviceName = VaultRepository.deviceName()
            try VaultRepository.shared.replaceSnapshot(snapshot, persist: true, emitChange: false)
            try await saveLocalSnapshot(snapshot)
        } catch {
            lastError = error
            logger.error("overwriteRemoteWithLocal failed: \(error.localizedDescription)")
            state = .needsAttention(.syncError(message: error.localizedDescription))
        }
    }

    func deleteRemoteVault() async throws {
        let tombstone = try await CloudVaultStore.shared.deleteRemoteVault(
            deviceID: VaultRepository.deviceID(),
            deviceName: VaultRepository.deviceName()
        )
        lastSyncedRevision = nil
        acknowledgedDeletedRemoteRevision = tombstone.revision
        lastSyncedAt = .now
    }

    private func handleDeletedManifest(_ manifest: CloudVaultManifest) {
        let local = VaultRepository.shared.snapshot
        if !local.hasData || acknowledgedDeletedRemoteRevision == manifest.revision {
            acknowledgedDeletedRemoteRevision = manifest.revision
            lastSyncedRevision = nil
            state = .ready
            lastSyncedAt = .now
            return
        }

        state = .remoteDeleted(
            revision: manifest.revision,
            remoteUpdatedAt: manifest.updatedAt,
            remoteUpdatedByDeviceName: manifest.updatedByDeviceName
        )
    }

    private func saveLocalSnapshot(_ snapshot: VaultSnapshot) async throws {
        guard snapshot.hasData else {
            state = .ready
            return
        }

        _ = try await CloudVaultStore.shared.save(snapshot: snapshot)
        lastSyncedRevision = snapshot.revision
        acknowledgedDeletedRemoteRevision = nil
        lastSyncedAt = .now
        state = .ready
    }
}
