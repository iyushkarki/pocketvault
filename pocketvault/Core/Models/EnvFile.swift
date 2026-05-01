import SwiftData
import Foundation

@Model
final class EnvFile {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \EnvEntry.file)
    var entries: [EnvEntry]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
}
