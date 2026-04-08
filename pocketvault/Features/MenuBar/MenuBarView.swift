import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Environment(LockManager.self) private var lockManager
    @State private var selectedProject: Project?
    @State private var selectedFile: EnvFile?
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var viewModel = EnvEditorViewModel()
    @State private var copyFeedback = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if lockManager.isLocked {
                UnlockView(compact: true) {
                    lockManager.unlock()
                    viewModel.hideAllValues()
                }
            } else if let file = selectedFile {
                popoverFileView(file)
            } else if let project = selectedProject {
                popoverProjectView(project)
            } else {
                mainView
            }
        }
        .frame(width: AppTheme.Sizing.popoverWidth)
        .frame(maxHeight: AppTheme.Sizing.popoverMaxHeight)
        .background(AppTheme.background)
        .onAppear {
            viewModel.lockManager = lockManager
        }
        .onDisappear {
            selectedProject = nil
            selectedFile = nil
            searchQuery = ""
            isSearching = false
            copyFeedback = false
            viewModel.hideAllValues()
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if isSearching && !searchQuery.isEmpty {
                QuickSearchView(
                    query: searchQuery,
                    onSelectProject: { project in
                        isSearching = false
                        searchQuery = ""
                        selectedProject = project
                    },
                    onSelectFile: { file in
                        isSearching = false
                        searchQuery = ""
                        selectedProject = file.project
                        selectedFile = file
                    }
                )
            } else {
                projectListView
            }
            Divider()
            footerView
        }
    }

    private var headerView: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)

                TextField("Search...", text: $searchQuery)
                    .font(AppTheme.Fonts.body)
                    .textFieldStyle(.plain)
                    .onSubmit { isSearching = true }
                    .onChange(of: searchQuery) {
                        lockManager.recordActivity()
                        isSearching = !searchQuery.isEmpty
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.surfaceElevated)
            )

            SettingsLink {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.popoverPadding)
    }

    private var projectListView: some View {
        Group {
            if projects.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("No projects yet")
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Open the editor to create\nyour first project.")
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                List {
                    ForEach(projects) { project in
                        Button {
                            lockManager.recordActivity()
                            selectedProject = project
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.accent)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project.name)
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\((project.files ?? []).count) \((project.files ?? []).count == 1 ? "file" : "files")")
                                        .font(AppTheme.Fonts.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button {
                openManageWindow()
            } label: {
                Label("Manage", systemImage: "macwindow")
                    .font(AppTheme.Fonts.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .help("Open main window")

            Spacer()

            Button {
                viewModel.hideAllValues()
                lockManager.lock()
            } label: {
                Label("Lock", systemImage: "lock.fill")
                    .font(AppTheme.Fonts.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .help("Lock vault")
        }
        .padding(AppTheme.Spacing.popoverPadding)
    }

    private func popoverProjectView(_ project: Project) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    lockManager.recordActivity()
                    selectedProject = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Back to projects")

                Text(project.name)
                    .font(AppTheme.Fonts.title)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.popoverPadding)
            .padding(.vertical, AppTheme.Spacing.sm)

            Divider()

            let sortedFiles = (project.files ?? []).sorted { $0.updatedAt > $1.updatedAt }
            if sortedFiles.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("No files yet")
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                List {
                    ForEach(sortedFiles) { file in
                        Button {
                            lockManager.recordActivity()
                            selectedFile = file
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.accent)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name)
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\((file.entries ?? []).count) \((file.entries ?? []).count == 1 ? "key" : "keys")")
                                        .font(AppTheme.Fonts.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button {
                    selectedProject = nil
                    selectedFile = nil
                    openManageWindow()
                } label: {
                    Label("Manage", systemImage: "macwindow")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .help("Open main window")

                Spacer()

                Button {
                    viewModel.hideAllValues()
                    lockManager.lock()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .help("Lock vault")
            }
            .padding(AppTheme.Spacing.popoverPadding)
        }
    }

    private func popoverFileView(_ file: EnvFile) -> some View {
        let sortedEntries = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    lockManager.recordActivity()
                    viewModel.hideAllValues()
                    selectedFile = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Back to files")

                Text(file.name)
                    .font(AppTheme.Fonts.title)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.popoverPadding)
            .padding(.vertical, AppTheme.Spacing.sm)

            Divider()

            if sortedEntries.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("No entries yet")
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                List {
                    ForEach(sortedEntries) { entry in
                        EnvEntryRow(
                            entry: entry,
                            revealedValue: viewModel.revealedValue(for: entry),
                            onRevealToggle: { viewModel.toggleReveal(for: entry) },
                            onCopy: { viewModel.copyValue(for: entry) },
                            onCopyKey: { viewModel.copyKey(for: entry) }
                        )
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: AppTheme.Spacing.xs,
                            bottom: 0,
                            trailing: AppTheme.Spacing.xs
                        ))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button {
                    openManageWindow()
                } label: {
                    Label("Manage", systemImage: "macwindow")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .help("Open main window")

                Spacer()

                if !sortedEntries.isEmpty {
                    Button {
                        copyAllEntries(file)
                    } label: {
                        Label(
                            copyFeedback ? "Copied!" : "Copy All",
                            systemImage: copyFeedback ? "checkmark" : "doc.on.doc"
                        )
                        .font(AppTheme.Fonts.button)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copyFeedback ? AppTheme.success : AppTheme.textSecondary)
                    .disabled(copyFeedback)
                    .help("Copy all entries as KEY=VALUE")
                }

                Button {
                    viewModel.hideAllValues()
                    lockManager.lock()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .help("Lock vault")
            }
            .padding(AppTheme.Spacing.popoverPadding)
        }
    }

    private func openManageWindow() {
        openWindow(id: "main")
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }

    private func copyAllEntries(_ file: EnvFile) {
        lockManager.recordActivity()
        do {
            let content = try ExportService.copyAllEntries(file)
            ClipboardManager.shared.copyToClipboard(content)
            copyFeedback = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copyFeedback = false
            }
        } catch {
            viewModel.errorMessage = "Failed to copy: \(error.localizedDescription)"
        }
    }
}
