import SwiftUI
import SwiftData

struct QuickSearchView: View {
    let query: String
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    let onSelectProject: (Project) -> Void
    let onSelectFile: (EnvFile) -> Void

    @State private var results = SearchResults(projects: [], files: [], entries: [])

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else if results.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("No results for \"\(query)\"")
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                searchResultsList
            }
        }
        .task(id: query) {
            results = SearchService(modelContext: modelContext).search(query: query)
        }
    }

    private var searchResultsList: some View {
        List {
            if !results.projects.isEmpty {
                Section("Projects") {
                    ForEach(results.projects) { project in
                        Button {
                            lockManager.recordActivity()
                            onSelectProject(project)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.accent)
                                Text(project.name)
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !results.files.isEmpty {
                Section("Files") {
                    ForEach(results.files) { file in
                        Button {
                            lockManager.recordActivity()
                            onSelectFile(file)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name)
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    if let projectName = file.project?.name {
                                        Text(projectName)
                                            .font(AppTheme.Fonts.caption)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !results.entries.isEmpty {
                Section("Keys") {
                    ForEach(results.entries) { entry in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Button {
                                if let file = entry.file {
                                    lockManager.recordActivity()
                                    onSelectFile(file)
                                }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.key)
                                            .font(AppTheme.Fonts.key)
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if let fileName = entry.file?.name {
                                            Text(fileName)
                                                .font(AppTheme.Fonts.caption)
                                                .foregroundStyle(AppTheme.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            KeyCopyButton(entry: entry)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct KeyCopyButton: View {
    let entry: EnvEntry
    @Environment(LockManager.self) private var lockManager
    @State private var copied = false

    var body: some View {
        Button {
            lockManager.recordActivity()
            ClipboardManager.shared.copyToClipboard(entry.value)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? AppTheme.success : AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Copy value")
    }
}
