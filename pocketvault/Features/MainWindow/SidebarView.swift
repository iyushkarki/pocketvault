import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedFile: EnvFile?
    @Binding var expandedProjectIDs: Set<UUID>
    let viewModel: EnvEditorViewModel

    @State private var showCreateProjectSheet = false
    @State private var projectToEdit: Project?
    @State private var projectToDelete: Project?
    @State private var showCreateFileSheet: Project?
    @State private var fileToEdit: EnvFile?
    @State private var fileToDelete: EnvFile?
    @State private var showDeleteProjectAlert = false
    @State private var showDeleteFileAlert = false

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
        .alert("Delete Project", isPresented: $showDeleteProjectAlert, presenting: projectToDelete) { project in
            Button("Cancel", role: .cancel) { projectToDelete = nil }
            Button("Delete", role: .destructive) { deleteProject(project) }
        } message: { project in
            Text("Delete \"\(project.name)\" and all its files? This cannot be undone.")
        }
        .alert("Delete File", isPresented: $showDeleteFileAlert, presenting: fileToDelete) { file in
            Button("Cancel", role: .cancel) { fileToDelete = nil }
            Button("Delete", role: .destructive) { deleteFile(file) }
        } message: { file in
            Text("Delete \"\(file.name)\" and all its entries? This cannot be undone.")
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
                            .contextMenu {
                                Button("Rename") { fileToEdit = file }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    fileToDelete = file
                                    showDeleteFileAlert = true
                                }
                            }
                    }
                } label: {
                    projectLabel(project)
                }
                .contextMenu {
                    Button("Add File") { showCreateFileSheet = project }
                    Divider()
                    Button("Edit") { projectToEdit = project }
                    Divider()
                    Button("Delete", role: .destructive) {
                        projectToDelete = project
                        showDeleteProjectAlert = true
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
        }
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
