import SwiftData
import Foundation

enum ExportError: LocalizedError {
    case duplicateFileNames([String])

    var errorDescription: String? {
        switch self {
        case .duplicateFileNames(let names):
            let joinedNames = names.sorted().joined(separator: ", ")
            return "Cannot export project because multiple files would overwrite each other: \(joinedNames)."
        }
    }
}

enum ExportService {
    static func exportFile(_ file: EnvFile) -> String {
        let sortedEntries = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var lines: [String] = []
        for entry in sortedEntries {
            if entry.isComment {
                lines.append("# \(entry.commentText)")
            } else {
                lines.append(EnvParser.format([(key: entry.key, value: entry.value)]))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func exportProject(_ project: Project) throws -> [(fileName: String, content: String)] {
        let files = (project.files ?? []).sorted { $0.name < $1.name }
        let duplicateNames = Dictionary(grouping: files, by: { $0.name.lowercased() })
            .values
            .compactMap { groupedFiles in
                groupedFiles.count > 1 ? groupedFiles.first?.name : nil
            }
        guard duplicateNames.isEmpty else {
            throw ExportError.duplicateFileNames(duplicateNames)
        }
        return files.map { file in
            (fileName: file.name, content: exportFile(file))
        }
    }

    static func copyAllEntries(_ file: EnvFile) -> String {
        exportFile(file)
    }
}
