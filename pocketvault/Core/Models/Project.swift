import SwiftData
import Foundation

@Model
final class Project {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var projectDescription: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \EnvFile.project)
    var files: [EnvFile]?

    init(name: String, description: String? = nil) {
        self.id = UUID()
        self.name = name
        self.projectDescription = description
        self.createdAt = .now
        self.updatedAt = .now
    }
}
