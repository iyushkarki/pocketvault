import Foundation
import CryptoKit
import CommonCrypto

enum CryptoError: LocalizedError {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case invalidVaultFormat
    case unsupportedVersion
    case passwordVerificationFailed

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed: return "Failed to derive encryption key."
        case .encryptionFailed: return "Encryption failed."
        case .decryptionFailed: return "Decryption failed. The password may be incorrect."
        case .invalidData: return "Invalid data."
        case .invalidVaultFormat: return "Invalid vault file format."
        case .unsupportedVersion: return "Unsupported vault file version."
        case .passwordVerificationFailed: return "Incorrect password."
        }
    }
}

enum CryptoService {
    static let pbkdf2Iterations: UInt32 = 260_000
    static let saltLength = 16
    static let keyLength = 32

    private static let vaultMagic: [UInt8] = [0x50, 0x56, 0x4C, 0x54] // "PVLT"
    private static let vaultVersion: UInt8 = 1

    // MARK: - Key Derivation

    static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoError.keyDerivationFailed
        }
        var derivedKey = Data(count: keyLength)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    static func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        salt.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        return salt
    }

    // MARK: - Verification Hash

    static func createVerificationHash(from password: String, salt: Data) throws -> Data {
        let key = try deriveKey(from: password, salt: salt)
        let reference = Data("pocketvault-verification".utf8)
        let sealed = try AES.GCM.seal(reference, using: key)
        return sealed.combined!
    }

    static func verifyPassword(_ password: String, salt: Data, verificationHash: Data) throws -> Bool {
        let key = try deriveKey(from: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: verificationHash)
            let decrypted = try AES.GCM.open(box, using: key)
            return decrypted == Data("pocketvault-verification".utf8)
        } catch {
            return false
        }
    }

    // MARK: - AES-256-GCM Encrypt / Decrypt

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard let sealed = try? AES.GCM.seal(data, using: key) else {
            throw CryptoError.encryptionFailed
        }
        guard let combined = sealed.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    // MARK: - .envvault Format

    // Format: [magic 4B][version 1B][salt 16B][iterations 4B][encrypted data (nonce+ciphertext+tag)]

    static func encryptVault(_ plaintext: Data, password: String) throws -> Data {
        let salt = generateSalt()
        let key = try deriveKey(from: password, salt: salt)

        guard let sealed = try? AES.GCM.seal(plaintext, using: key),
              let encryptedData = sealed.combined else {
            throw CryptoError.encryptionFailed
        }

        var output = Data()
        output.append(contentsOf: vaultMagic)
        output.append(vaultVersion)
        output.append(salt)

        var iterations = pbkdf2Iterations.bigEndian
        output.append(Data(bytes: &iterations, count: 4))

        output.append(encryptedData)
        return output
    }

    static func decryptVault(_ data: Data, password: String) throws -> Data {
        // magic(4) + version(1) + salt(16) + iterations(4) = 25 bytes minimum header
        guard data.count > 25 else { throw CryptoError.invalidVaultFormat }

        let magic = [UInt8](data[0..<4])
        guard magic == vaultMagic else { throw CryptoError.invalidVaultFormat }

        let version = data[4]
        guard version == vaultVersion else { throw CryptoError.unsupportedVersion }

        let salt = data[5..<21]
        let iterationsData = data[21..<25]
        let iterations = iterationsData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }

        let encryptedData = data[25...]

        var derivedKey = Data(count: keyLength)
        let passwordData = password.data(using: .utf8)!
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }

        let key = SymmetricKey(data: derivedKey)
        do {
            let box = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
