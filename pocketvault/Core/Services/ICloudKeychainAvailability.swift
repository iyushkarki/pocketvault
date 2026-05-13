import Foundation
import Security
import AppKit
import os

enum ICloudKeychainStatus: Equatable {
    case available
    case unavailable(reason: String)
    case unknown
}

enum ICloudKeychainAvailability {
    nonisolated private static let probeAccount = "pocketvault.icloud.probe"
    nonisolated private static let serviceName = "\(Bundle.main.bundleIdentifier ?? "app.pocketvault").keychain"
    nonisolated private static let logger = Logger(subsystem: "app.pocketvault", category: "ICloudKeychainAvailability")

    nonisolated static func check() -> ICloudKeychainStatus {
        let payload = UUID().uuidString.data(using: .utf8) ?? Data()
        let cleanupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: probeAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: probeAccount,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: payload
        ]

        SecItemDelete(cleanupQuery as CFDictionary)
        var addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            SecItemDelete(cleanupQuery as CFDictionary)
            addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        }

        defer {
            SecItemDelete(cleanupQuery as CFDictionary)
        }

        guard addStatus == errSecSuccess else {
            logger.error("iCloud Keychain probe write failed: \(addStatus)")
            return .unavailable(reason: reasonForStatus(addStatus))
        }

        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: probeAccount,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)

        if readStatus == errSecSuccess, let data = result as? Data, data == payload {
            return .available
        }

        logger.error("iCloud Keychain probe read failed: \(readStatus)")
        return .unavailable(reason: reasonForStatus(readStatus))
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func reasonForStatus(_ status: OSStatus) -> String {
        switch status {
        case errSecNotAvailable:
            return "iCloud Keychain is not enabled on this Mac."
        case errSecAuthFailed:
            return "Authentication required to access iCloud Keychain."
        case errSecUserCanceled:
            return "Access to iCloud Keychain was canceled."
        default:
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error \(status)."
        }
    }
}
