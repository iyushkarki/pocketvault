import Foundation
import CryptoKit
import Security

enum VaultKeyServiceError: LocalizedError {
    case invalidKeyData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKeyData:
            return "Stored vault key data is invalid."
        case .unexpectedStatus(let status):
            return "Vault key error: \(status)."
        }
    }
}

final class VaultKeyService {
    static let shared = VaultKeyService()

    private let service = AppConfig.keychainServiceName
    private let account = AppConfig.vaultKeyIdentifier

    private init() {}

    func getOrCreateKey(syncable: Bool) throws -> SymmetricKey {
        if let existing = try readKey(syncable: syncable) {
            return existing
        }

        if !syncable, let syncableReplica = try readKey(syncable: true) {
            try storeKey(syncableReplica, syncable: false)
            return syncableReplica
        }

        let key = SymmetricKey(size: .bits256)
        try storeKey(key, syncable: syncable)
        return key
    }

    func readKey(syncable: Bool) throws -> SymmetricKey? {
        var query = baseQuery(syncable: syncable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw VaultKeyServiceError.unexpectedStatus(status)
        }

        guard let data = result as? Data, data.count == 32 else {
            throw VaultKeyServiceError.invalidKeyData
        }

        return SymmetricKey(data: data)
    }

    func storeKey(_ key: SymmetricKey, syncable: Bool) throws {
        let data = key.rawData
        var addQuery = baseQuery(syncable: syncable)
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(syncable: syncable) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw VaultKeyServiceError.unexpectedStatus(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw VaultKeyServiceError.unexpectedStatus(status)
        }
    }

    func deleteAllKeys() throws {
        for syncable in [false, true] {
            let status = SecItemDelete(baseQuery(syncable: syncable) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw VaultKeyServiceError.unexpectedStatus(status)
            }
        }
    }

    func deleteLocalKey() throws {
        let status = SecItemDelete(baseQuery(syncable: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeyServiceError.unexpectedStatus(status)
        }
    }

    func deleteSyncableKey() throws {
        let status = SecItemDelete(baseQuery(syncable: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeyServiceError.unexpectedStatus(status)
        }
    }

    func ensureSyncableReplicaFromLocalKey() throws -> SymmetricKey {
        if let syncableKey = try readKey(syncable: true) {
            return syncableKey
        }

        let localKey = try getOrCreateKey(syncable: false)
        try storeKey(localKey, syncable: true)
        return localKey
    }

    func replaceLocalKey(with syncableKey: SymmetricKey) throws {
        try storeKey(syncableKey, syncable: false)
    }

    private func baseQuery(syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if syncable {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            query[kSecAttrSynchronizable as String] = true
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
        }

        return query
    }
}

private extension SymmetricKey {
    var rawData: Data {
        withUnsafeBytes { Data($0) }
    }
}
