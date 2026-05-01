import Foundation
import CryptoKit
import os

enum EncryptedVaultStoreError: LocalizedError {
    case missingVault
    case serializationFailed
    case deserializationFailed
    case unrecoverable(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingVault:
            return "No local vault was found."
        case .serializationFailed:
            return "Failed to serialize the vault."
        case .deserializationFailed:
            return "Failed to read the local vault."
        case .unrecoverable(let underlying):
            return "The local vault could not be decrypted: \(underlying.localizedDescription)"
        }
    }
}

final class EncryptedVaultStore {
    static let shared = EncryptedVaultStore()

    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "EncryptedVaultStore")

    private init() {}

    func load(syncableKey: Bool) throws -> VaultSnapshot? {
        let url = try vaultURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let encrypted = try Data(contentsOf: url)
        let key = try VaultKeyService.shared.getOrCreateKey(syncable: syncableKey)

        let decrypted: Data
        do {
            decrypted = try CryptoService.decrypt(encrypted, using: key)
        } catch {
            logger.error("Vault decryption failed: \(error.localizedDescription, privacy: .public)")
            throw EncryptedVaultStoreError.unrecoverable(underlying: error)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(VaultSnapshot.self, from: decrypted)
        } catch {
            logger.error("Vault decoding failed: \(error.localizedDescription, privacy: .public)")
            throw EncryptedVaultStoreError.unrecoverable(underlying: error)
        }
    }

    func quarantineCorruptVault() throws -> URL {
        let url = try vaultURL()
        return try quarantineCorruptVault(at: url)
    }

    private func quarantineCorruptVault(at url: URL) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(timestamp)")
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    func save(_ snapshot: VaultSnapshot, syncableKey: Bool) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            throw EncryptedVaultStoreError.serializationFailed
        }

        let key = try VaultKeyService.shared.getOrCreateKey(syncable: syncableKey)
        let encrypted = try CryptoService.encrypt(data, using: key)
        let url = try vaultURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encrypted.write(to: url, options: .atomic)
    }

    func deleteLocalVault() throws {
        let url = try vaultURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func localVaultExists() throws -> Bool {
        try FileManager.default.fileExists(atPath: vaultURL().path)
    }

    private func vaultURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent(AppConfig.bundleIdentifier, isDirectory: true)
            .appendingPathComponent(AppConfig.canonicalVaultFileName)
    }
}
