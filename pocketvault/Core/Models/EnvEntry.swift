import SwiftData
import Foundation

@Model
final class EnvEntry {
    var id: UUID = UUID()
    var key: String = ""
    var keychainIdentifier: String = ""
    var sortOrder: Int = 0
    var comment: String?
    var isComment: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var file: EnvFile?

    init(key: String, sortOrder: Int = 0, isComment: Bool = false, comment: String? = nil) {
        let entryId = UUID()
        self.id = entryId
        self.key = key
        self.keychainIdentifier = "\(AppConfig.keychainIdentifierPrefix)-\(entryId.uuidString)"
        self.sortOrder = sortOrder
        self.isComment = isComment
        self.comment = comment
        self.createdAt = .now
        self.updatedAt = .now
    }

    var commentText: String {
        if let comment, !comment.isEmpty {
            return comment
        }
        return isComment ? key : ""
    }
}
