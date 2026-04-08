import SwiftData
import Foundation

struct SearchResults {
    var projects: [Project]
    var files: [EnvFile]
    var entries: [EnvEntry]

    var isEmpty: Bool { projects.isEmpty && files.isEmpty && entries.isEmpty }
}

final class SearchService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(query: String) -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(projects: [], files: [], entries: [])
        }

        let projects = searchProjects(query: trimmed)
        let files = searchFiles(query: trimmed)
        let entries = searchEntries(query: trimmed)

        return SearchResults(projects: projects, files: files, entries: entries)
    }

    private func searchProjects(query: String) -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.name.localizedStandardContains(query) }
        } catch {
            print("[SearchService] Failed to fetch projects: \(error)")
            return []
        }
    }

    private func searchFiles(query: String) -> [EnvFile] {
        let descriptor = FetchDescriptor<EnvFile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.name.localizedStandardContains(query) }
        } catch {
            print("[SearchService] Failed to fetch files: \(error)")
            return []
        }
    }

    private func searchEntries(query: String) -> [EnvEntry] {
        let descriptor = FetchDescriptor<EnvEntry>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { !$0.isComment && $0.key.localizedStandardContains(query) }
        } catch {
            print("[SearchService] Failed to fetch entries: \(error)")
            return []
        }
    }
}
