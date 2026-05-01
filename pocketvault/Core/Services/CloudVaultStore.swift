import Foundation
import CloudKit
import CryptoKit

enum CloudVaultStoreError: LocalizedError {
    case manifestEncodingFailed
    case manifestDecodingFailed
    case payloadAssetMissing
    case payloadEncodingFailed
    case payloadDecodingFailed
    case syncKeyUnavailable
    case cloudPayloadUnreadable

    var errorDescription: String? {
        switch self {
        case .manifestEncodingFailed:
            return "Failed to encode the cloud manifest."
        case .manifestDecodingFailed:
            return "Failed to decode the cloud manifest."
        case .payloadAssetMissing:
            return "The cloud vault payload is missing."
        case .payloadEncodingFailed:
            return "Failed to encode the cloud vault."
        case .payloadDecodingFailed:
            return "Failed to decode the cloud vault."
        case .syncKeyUnavailable:
            return "Your iCloud vault key is not available on this Mac yet. Make sure iCloud Keychain is enabled and fully synced."
        case .cloudPayloadUnreadable:
            return "The vault stored in iCloud was encrypted with a key this Mac doesn't have. Overwrite the cloud copy with this Mac's vault, or disable sync."
        }
    }
}

final class CloudVaultStore {
    static let shared = CloudVaultStore()

    static let manifestSubscriptionID = "pocketvault-manifest-subscription"

    private let container = CKContainer(identifier: "iCloud.app.pocketvault")
    private let manifestRecordType = "PocketVaultManifest"
    private let payloadRecordType = "PocketVaultPayload"
    private let manifestRecordID = CKRecord.ID(recordName: "canonical-vault-manifest")
    private let payloadRecordID = CKRecord.ID(recordName: "canonical-vault-payload")

    private init() {}

    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    func fetchManifest() async throws -> CloudVaultManifest? {
        do {
            let record = try await database.record(for: manifestRecordID)
            return try decodeManifest(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func fetchSnapshot() async throws -> VaultSnapshot? {
        do {
            let record = try await database.record(for: payloadRecordID)
            return try decodeSnapshot(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    @discardableResult
    func save(snapshot: VaultSnapshot) async throws -> CloudVaultManifest {
        let manifest = try makeManifest(from: snapshot)
        let payloadRecord = (try? await database.record(for: payloadRecordID)) ?? CKRecord(recordType: payloadRecordType, recordID: payloadRecordID)
        payloadRecord["revision"] = snapshot.revision as CKRecordValue
        payloadRecord["updatedAt"] = snapshot.updatedAt as CKRecordValue
        let asset = try makePayloadAsset(for: snapshot)
        payloadRecord["payload"] = asset
        defer { asset.fileURL.map { try? FileManager.default.removeItem(at: $0) } }

        let manifestRecord = (try? await database.record(for: manifestRecordID)) ?? CKRecord(recordType: manifestRecordType, recordID: manifestRecordID)
        try encodeManifest(manifest, into: manifestRecord)

        try await database.modifyRecords(saving: [payloadRecord, manifestRecord], deleting: [], savePolicy: .ifServerRecordUnchanged)
        return manifest
    }

    func deleteRemoteVault(deviceID: String, deviceName: String) async throws {
        let tombstone = CloudVaultManifest(
            revision: UUID().uuidString,
            payloadHash: "",
            updatedAt: .now,
            updatedByDeviceID: deviceID,
            updatedByDeviceName: deviceName,
            projectCount: 0,
            fileCount: 0,
            entryCount: 0,
            isDeleted: true
        )
        let manifestRecord = (try? await database.record(for: manifestRecordID)) ?? CKRecord(recordType: manifestRecordType, recordID: manifestRecordID)
        try encodeManifest(tombstone, into: manifestRecord)
        try await database.modifyRecords(saving: [manifestRecord], deleting: [payloadRecordID], savePolicy: .ifServerRecordUnchanged)
    }

    func ensureManifestSubscription() async throws {
        let subscriptionID = Self.manifestSubscriptionID
        if (try? await database.subscription(for: subscriptionID)) != nil {
            return
        }
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: manifestRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        try await database.save(subscription: subscription)
    }

    func payloadHash(for snapshot: VaultSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(snapshot.projects) else {
            throw CloudVaultStoreError.payloadEncodingFailed
        }
        return SHA256.hash(data: encoded).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func makeManifest(from snapshot: VaultSnapshot) throws -> CloudVaultManifest {
        let hash = try payloadHash(for: snapshot)
        return CloudVaultManifest(
            revision: snapshot.revision,
            payloadHash: hash,
            updatedAt: snapshot.updatedAt,
            updatedByDeviceID: snapshot.updatedByDeviceID,
            updatedByDeviceName: snapshot.updatedByDeviceName,
            projectCount: snapshot.projectCount,
            fileCount: snapshot.fileCount,
            entryCount: snapshot.entryCount,
            isDeleted: false
        )
    }

    private func encodeManifest(_ manifest: CloudVaultManifest, into record: CKRecord) throws {
        record["revision"] = manifest.revision as CKRecordValue
        record["payloadHash"] = manifest.payloadHash as CKRecordValue
        record["updatedAt"] = manifest.updatedAt as CKRecordValue
        record["updatedByDeviceID"] = manifest.updatedByDeviceID as CKRecordValue
        record["updatedByDeviceName"] = manifest.updatedByDeviceName as CKRecordValue
        record["projectCount"] = NSNumber(value: manifest.projectCount)
        record["fileCount"] = NSNumber(value: manifest.fileCount)
        record["entryCount"] = NSNumber(value: manifest.entryCount)
        record["isDeleted"] = NSNumber(value: manifest.isDeleted)
    }

    private func decodeManifest(from record: CKRecord) throws -> CloudVaultManifest {
        guard let revision = record["revision"] as? String,
              let payloadHash = record["payloadHash"] as? String,
              let updatedAt = record["updatedAt"] as? Date,
              let updatedByDeviceID = record["updatedByDeviceID"] as? String,
              let projectCount = record["projectCount"] as? NSNumber,
              let fileCount = record["fileCount"] as? NSNumber,
              let entryCount = record["entryCount"] as? NSNumber,
              let isDeleted = record["isDeleted"] as? NSNumber else {
            throw CloudVaultStoreError.manifestDecodingFailed
        }

        let updatedByDeviceName = (record["updatedByDeviceName"] as? String) ?? ""

        return CloudVaultManifest(
            revision: revision,
            payloadHash: payloadHash,
            updatedAt: updatedAt,
            updatedByDeviceID: updatedByDeviceID,
            updatedByDeviceName: updatedByDeviceName,
            projectCount: projectCount.intValue,
            fileCount: fileCount.intValue,
            entryCount: entryCount.intValue,
            isDeleted: isDeleted.boolValue
        )
    }

    private func makePayloadAsset(for snapshot: VaultSnapshot) throws -> CKAsset {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(snapshot) else {
            throw CloudVaultStoreError.payloadEncodingFailed
        }

        let key = try VaultKeyService.shared.ensureSyncableReplicaFromLocalKey()
        let encrypted = try CryptoService.encrypt(encoded, using: key)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pocketvault")
        try encrypted.write(to: tempURL, options: .atomic)
        return CKAsset(fileURL: tempURL)
    }

    private func decodeSnapshot(from record: CKRecord) throws -> VaultSnapshot {
        guard let asset = record["payload"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudVaultStoreError.payloadAssetMissing
        }

        let encrypted = try Data(contentsOf: fileURL)
        guard let key = try VaultKeyService.shared.readKey(syncable: true) else {
            throw CloudVaultStoreError.syncKeyUnavailable
        }
        let decrypted: Data
        do {
            decrypted = try CryptoService.decrypt(encrypted, using: key)
        } catch {
            throw CloudVaultStoreError.cloudPayloadUnreadable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(VaultSnapshot.self, from: decrypted) else {
            throw CloudVaultStoreError.payloadDecodingFailed
        }
        return snapshot
    }
}

private extension CKDatabase {
    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    func subscription(for subscriptionID: CKSubscription.ID) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let subscription {
                    continuation.resume(returning: subscription)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    func save(subscription: CKSubscription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            save(subscription) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func modifyRecords(saving records: [CKRecord], deleting recordIDs: [CKRecord.ID], savePolicy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: recordIDs)
            operation.savePolicy = savePolicy
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            add(operation)
        }
    }
}
