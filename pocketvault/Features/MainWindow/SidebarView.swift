import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SidebarView: View {
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedFile: EnvFile?
    @Binding var expandedProjectIDs: Set<UUID>
    let viewModel: EnvEditorViewModel
    let onImportFile: (URL, Project?, EnvFile?, Bool) -> Void

    @State private var showCreateProjectSheet = false
    @State private var projectToEdit: Project?
    @State private var projectToDelete: Project?
    @State private var showCreateFileSheet: Project?
    @State private var fileToEdit: EnvFile?
    @State private var fileToDelete: EnvFile?
    @State private var hoveredProjectID: UUID?
    @State private var hoveredFileID: UUID?

    var body: some View {
        Group {
            if projects.isEmpty {
                sidebarEmptyState
            } else {
                projectList
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showCreateProjectSheet = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                SyncStatusIndicator()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .frame(minWidth: AppTheme.Sizing.sidebarMinWidth)
        .sheet(isPresented: $showCreateProjectSheet) {
            CreateProjectSheet { file in
                selectedFile = file
            }
        }
        .sheet(item: $projectToEdit) { project in
            EditProjectSheet(project: project)
        }
        .sheet(item: $showCreateFileSheet) { project in
            CreateFileSheet(project: project) { file in
                selectedFile = file
            }
        }
        .sheet(item: $fileToEdit) { file in
            EditFileSheet(file: file)
        }
        .sheet(item: $projectToDelete) { project in
            ConfirmDeleteSheet(
                title: "Delete Project",
                itemName: project.name,
                message: "This permanently deletes \"\(project.name)\", all files in the project, and all stored environment values.",
                confirmButtonTitle: "Delete Project"
            ) {
                deleteProject(project)
            }
        }
        .sheet(item: $fileToDelete) { file in
            ConfirmDeleteSheet(
                title: "Delete File",
                itemName: file.name,
                message: "This permanently deletes \"\(file.name)\" and all stored environment values in the file.",
                confirmButtonTitle: "Delete File"
            ) {
                deleteFile(file)
            }
        }
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No projects yet")
                .font(AppTheme.Fonts.sectionHeader)
                .foregroundStyle(AppTheme.textSecondary)
            Button("Create Project") {
                showCreateProjectSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
        List(selection: $selectedFile) {
            ForEach(projects) { project in
                DisclosureGroup(isExpanded: expandedBinding(for: project)) {
                    ForEach(sortedFiles(for: project)) { file in
                        fileRow(file)
                            .tag(file)
                            .onHover { isHovered in
                                hoveredFileID = isHovered ? file.id : (hoveredFileID == file.id ? nil : hoveredFileID)
                            }
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                handleDrop(providers, project: project, file: file, createNewFile: false)
                            }
                            .contextMenu {
                                Button("Rename File") { fileToEdit = file }
                                Divider()
                                Button("Delete File", role: .destructive) {
                                    fileToDelete = file
                                }
                            }
                    }
                } label: {
                    projectLabel(project)
                }
                .onHover { isHovered in
                    hoveredProjectID = isHovered ? project.id : (hoveredProjectID == project.id ? nil : hoveredProjectID)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers, project: project, file: nil, createNewFile: true)
                }
                .contextMenu {
                    Button("Add File") { showCreateFileSheet = project }
                    Divider()
                    Button("Rename Project") { projectToEdit = project }
                    Divider()
                    Button("Delete Project", role: .destructive) {
                        projectToDelete = project
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sortedFiles(for project: Project) -> [EnvFile] {
        (project.files ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    private func expandedBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { expandedProjectIDs.contains(project.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedProjectIDs.insert(project.id)
                } else {
                    expandedProjectIDs.remove(project.id)
                }
            }
        )
    }

    private func projectLabel(_ project: Project) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.accent)
            Text(project.name)
                .font(AppTheme.Fonts.body)
                .lineLimit(1)

            Spacer()

            Text("\((project.files ?? []).count)")
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Button {
                showCreateFileSheet = project
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Add file to \(project.name)")

            Menu {
                Button("Add File") { showCreateFileSheet = project }
                Button("Rename Project") { projectToEdit = project }
                Divider()
                Button("Delete Project", role: .destructive) {
                    projectToDelete = project
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(hoveredProjectID == project.id ? 1 : 0.55)
            .help("Project actions")
        }
    }

    private func fileRow(_ file: EnvFile) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Text(file.name)
                .font(AppTheme.Fonts.body)
                .lineLimit(1)

            Spacer()

            Text("\((file.entries ?? []).count)")
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Menu {
                Button("Rename File") { fileToEdit = file }
                Divider()
                Button("Delete File", role: .destructive) {
                    fileToDelete = file
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(hoveredFileID == file.id || selectedFile?.id == file.id ? 1 : 0.55)
            .help("File actions")
        }
    }

    private func handleDrop(
        _ providers: [NSItemProvider],
        project: Project?,
        file: EnvFile?,
        createNewFile: Bool
    ) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                onImportFile(url, project, file, createNewFile)
            }
        }
        return true
    }

    private func deleteProject(_ project: Project) {
        if selectedFile?.project?.id == project.id {
            selectedFile = nil
        }
        do {
            try viewModel.deleteProject(project, context: modelContext)
        } catch {
            viewModel.errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
        projectToDelete = nil
    }

    private func deleteFile(_ file: EnvFile) {
        if selectedFile?.id == file.id {
            selectedFile = nil
        }
        do {
            try viewModel.deleteFile(file, context: modelContext)
        } catch {
            viewModel.errorMessage = "Failed to delete file: \(error.localizedDescription)"
        }
        fileToDelete = nil
    }
}
