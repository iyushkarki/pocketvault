import Foundation

struct CloudVaultManifest: Codable, Equatable {
    var revision: String
    var payloadHash: String
    var updatedAt: Date
    var updatedByDeviceID: String
    var updatedByDeviceName: String
    var projectCount: Int
    var fileCount: Int
    var entryCount: Int
    var isDeleted: Bool
}
