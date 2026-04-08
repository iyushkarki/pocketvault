import Security
import Foundation
import os

protocol KeychainServiceProtocol {
    func setValue(_ value: String, for identifier: String) throws
    func getValue(for identifier: String) throws -> String?
    func updateValue(_ value: String, for identifier: String) throws
    func deleteValue(for identifier: String) throws
    func deleteAll() throws
    func listAllAccounts() -> [String]
}

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidData
    case unexpectedStatus(OSStatus)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Keychain item not found."
        case .duplicateItem: return "Keychain item already exists."
        case .invalidData: return "Keychain item data is invalid."
        case .unexpectedStatus(let status): return "Keychain error: \(status)."
        case .migrationFailed(let reason): return "Keychain migration failed: \(reason)"
        }
    }
}

final class KeychainService: KeychainServiceProtocol {
    static let shared = KeychainService()

    private let service = AppConfig.keychainServiceName
    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "KeychainService")

    var syncEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)
    }

    private init() {}

    // MARK: - CRUD

    func setValue(_ value: String, for identifier: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        var query = baseQuery(for: identifier)
        query[kSecValueData as String] = data
        applySyncAttributes(to: &query)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try updateValue(value, for: identifier)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getValue(for identifier: String) throws -> String? {
        var query = searchQuery(for: identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    func updateValue(_ value: String, for identifier: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        let query = searchQuery(for: identifier)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try setValue(value, for: identifier)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func deleteValue(for identifier: String) throws {
        let localQuery = localOnlyQuery(for: identifier)
        let localStatus = SecItemDelete(localQuery as CFDictionary)
        if localStatus != errSecSuccess && localStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(localStatus)
        }

        let syncQuery = syncableQuery(for: identifier)
        let syncStatus = SecItemDelete(syncQuery as CFDictionary)
        if syncStatus != errSecSuccess && syncStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(syncStatus)
        }
    }

    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func listAllAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Migration

    func migrateToSyncable() throws -> Int {
        let localAccounts = listLocalOnlyAccounts()
        guard !localAccounts.isEmpty else { return 0 }

        let defaults = UserDefaults.standard
        let migratedSet = Set(defaults.stringArray(forKey: AppConfig.UserDefaultsKey.keychainMigrationProgress) ?? [])
        let remaining = localAccounts.filter { !migratedSet.contains($0) }

        Self.logger.info("Keychain migration: \(remaining.count) items to migrate (\(migratedSet.count) already done)")

        var migrated = migratedSet
        var count = 0

        for account in remaining {
            guard let value = try readLocalOnly(account) else { continue }

            try writeSyncable(value, for: account)
            try deleteLocalOnly(account)

            migrated.insert(account)
            defaults.set(Array(migrated), forKey: AppConfig.UserDefaultsKey.keychainMigrationProgress)
            count += 1
        }

        defaults.set(true, forKey: AppConfig.UserDefaultsKey.keychainMigrationComplete)
        defaults.removeObject(forKey: AppConfig.UserDefaultsKey.keychainMigrationProgress)
        Self.logger.info("Keychain migration complete: \(count) items migrated")
        return count
    }

    func migrateToLocalOnly() throws -> Int {
        let syncAccounts = listSyncableAccounts()
        guard !syncAccounts.isEmpty else { return 0 }

        Self.logger.info("Keychain revert: \(syncAccounts.count) items to revert to local-only")
        var count = 0

        for account in syncAccounts {
            guard let value = try readSyncable(account) else { continue }
            try writeLocalOnly(value, for: account)
            try deleteSyncable(account)
            count += 1
        }

        UserDefaults.standard.set(false, forKey: AppConfig.UserDefaultsKey.keychainMigrationComplete)
        Self.logger.info("Keychain revert complete: \(count) items reverted to local-only")
        return count
    }

    // MARK: - Private Helpers

    private func baseQuery(for identifier: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]
    }

    private func applySyncAttributes(to query: inout [String: Any]) {
        if syncEnabled {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            query[kSecAttrSynchronizable as String] = true
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }

    private func searchQuery(for identifier: String) -> [String: Any] {
        var query = baseQuery(for: identifier)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }

    private func localOnlyQuery(for identifier: String) -> [String: Any] {
        var query = baseQuery(for: identifier)
        query[kSecAttrSynchronizable as String] = false
        return query
    }

    private func syncableQuery(for identifier: String) -> [String: Any] {
        var query = baseQuery(for: identifier)
        query[kSecAttrSynchronizable as String] = true
        return query
    }

    // MARK: - Migration Helpers

    private func listLocalOnlyAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: false
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func listSyncableAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func readLocalOnly(_ identifier: String) throws -> String? {
        var query = localOnlyQuery(for: identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    private func readSyncable(_ identifier: String) throws -> String? {
        var query = syncableQuery(for: identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    private func writeSyncable(_ value: String, for identifier: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        var query = baseQuery(for: identifier)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        query[kSecAttrSynchronizable as String] = true

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = syncableQuery(for: identifier)
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func writeLocalOnly(_ value: String, for identifier: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        var query = baseQuery(for: identifier)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = localOnlyQuery(for: identifier)
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteLocalOnly(_ identifier: String) throws {
        let query = localOnlyQuery(for: identifier)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteSyncable(_ identifier: String) throws {
        let query = syncableQuery(for: identifier)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
