import SwiftData
import Foundation

@Model
final class EnvEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    var sortOrder: Int = 0
    var comment: String?
    var isComment: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var file: EnvFile?

    init(key: String, value: String = "", sortOrder: Int = 0, isComment: Bool = false, comment: String? = nil) {
        self.id = UUID()
        self.key = key
        self.value = value
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
