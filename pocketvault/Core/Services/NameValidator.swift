import Foundation

enum EnvKeyValidator {
    static func validate(_ key: String) -> String? {
        if key.isEmpty { return "Key cannot be empty." }
        if key.contains("=") || key.contains("\n") || key.contains("\r") || key.contains("\0") {
            return "Key cannot contain '=', newlines, or null characters."
        }
        return nil
    }
}

enum NameValidationError: LocalizedError {
    case invalidProjectName(String)
    case invalidFileName(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectName(let message), .invalidFileName(let message):
            return message
        }
    }
}

enum NameValidator {
    private static let fileNameRegex = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$|^\.[a-zA-Z0-9][a-zA-Z0-9._-]*$/

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validateProjectName(
        _ value: String,
        existingProjects: [Project],
        excluding projectID: UUID? = nil
    ) -> String? {
        let trimmed = normalize(value)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > 100 {
            return "Name must be 100 characters or less."
        }

        if existingProjects.contains(where: { project in
            project.id != projectID && project.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return "A project with this name already exists."
        }

        return nil
    }

    static func validateOptionalFileName(
        _ value: String,
        existingFiles: [EnvFile],
        excluding fileID: UUID? = nil
    ) -> String? {
        let trimmed = normalize(value)
        guard !trimmed.isEmpty else { return nil }
        return validateFileName(trimmed, existingFiles: existingFiles, excluding: fileID)
    }

    static func validateFileName(
        _ value: String,
        existingFiles: [EnvFile],
        excluding fileID: UUID? = nil
    ) -> String? {
        let trimmed = normalize(value)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.wholeMatch(of: fileNameRegex) == nil {
            return "Use letters, numbers, dots, underscores, or hyphens. Names may start with a dot, like .env."
        }

        if existingFiles.contains(where: { file in
            file.id != fileID && file.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return "A file with this name already exists."
        }

        return nil
    }

    static func requireProjectName(_ value: String, existingProjects: [Project]) throws -> String {
        let trimmed = normalize(value)
        if let error = validateProjectName(trimmed, existingProjects: existingProjects) {
            throw NameValidationError.invalidProjectName(error)
        }
        guard !trimmed.isEmpty else {
            throw NameValidationError.invalidProjectName("Project name is required.")
        }
        return trimmed
    }

    static func requireFileName(_ value: String, existingFiles: [EnvFile]) throws -> String {
        let trimmed = normalize(value)
        if let error = validateFileName(trimmed, existingFiles: existingFiles) {
            throw NameValidationError.invalidFileName(error)
        }
        guard !trimmed.isEmpty else {
            throw NameValidationError.invalidFileName("File name is required.")
        }
        return trimmed
    }

    static func uniqueProjectName(_ value: String, existingProjects: [Project]) -> String {
        let baseName = normalize(value).isEmpty ? "Imported Project" : normalize(value)
        var candidate = projectCandidate(baseName: baseName, suffix: nil)
        var suffix = 2

        while validateProjectName(candidate, existingProjects: existingProjects) != nil {
            candidate = projectCandidate(baseName: baseName, suffix: suffix)
            suffix += 1
        }

        return candidate
    }

    static func uniqueFileName(_ value: String, existingFiles: [EnvFile]) -> String {
        let baseName = normalize(value).isEmpty ? ".env" : normalize(value)
        var candidate = baseName
        var suffix = 2

        while validateFileName(candidate, existingFiles: existingFiles) != nil {
            candidate = "\(baseName)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private static func projectCandidate(baseName: String, suffix: Int?) -> String {
        let suffixText = suffix.map { " \($0)" } ?? ""
        let maxBaseLength = max(1, 100 - suffixText.count)
        let truncatedBase = String(baseName.prefix(maxBaseLength))
        return truncatedBase + suffixText
    }
}
