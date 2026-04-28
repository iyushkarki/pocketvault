import Foundation

struct VaultSnapshot: Codable, Equatable {
    var version: Int
    var revision: String
    var updatedAt: Date
    var updatedByDeviceID: String
    var updatedByDeviceName: String
    var projects: [Project]

    struct Project: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var description: String?
        var createdAt: Date
        var updatedAt: Date
        var files: [File]
    }

    struct File: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var entries: [Entry]
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID
        var key: String
        var value: String
        var sortOrder: Int
        var isComment: Bool
        var comment: String?
        var createdAt: Date
        var updatedAt: Date
    }
}

extension VaultSnapshot {
    static func empty(deviceID: String, deviceName: String) -> VaultSnapshot {
        VaultSnapshot(
            version: 1,
            revision: UUID().uuidString,
            updatedAt: .now,
            updatedByDeviceID: deviceID,
            updatedByDeviceName: deviceName,
            projects: []
        )
    }

    var hasData: Bool {
        !projects.isEmpty
    }

    var projectCount: Int {
        projects.count
    }

    var fileCount: Int {
        projects.reduce(0) { $0 + $1.files.count }
    }

    var entryCount: Int {
        projects.reduce(0) { count, project in
            count + project.files.reduce(0) { $0 + $1.entries.count }
        }
    }
}
