import SwiftUI
import SwiftData

struct EditProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    @Query(sort: \Project.name) private var projects: [Project]
    @Bindable var project: Project

    @State private var name: String
    @State private var description: String
    @State private var nameError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, description }

    private let originalName: String
    private let originalDescription: String

    init(project: Project) {
        self.project = project
        let n = project.name
        let d = project.projectDescription ?? ""
        _name = State(initialValue: n)
        _description = State(initialValue: d)
        originalName = n
        originalDescription = d
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nameError == nil
    }

    private var hasChanges: Bool {
        name != originalName || description != originalDescription
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Edit Project")
                .font(AppTheme.Fonts.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .onChange(of: name) {
                        lockManager.recordActivity()
                        validateName()
                    }

                if let nameError {
                    Text(nameError)
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.error)
                }

                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .description)
                    .onChange(of: description) { _, _ in
                        lockManager.recordActivity()
                    }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { saveProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 300)
        .interactiveDismissDisabled(hasChanges)
        .onAppear { focusedField = .name }
        .alert("Error", isPresented: $showSaveError, presenting: saveError) { _ in
            Button("OK") { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func validateName() {
        if NameValidator.normalize(name).isEmpty {
            nameError = nil
            return
        }
        nameError = NameValidator.validateProjectName(name, existingProjects: projects, excluding: project.id)
    }

    private func saveProject() {
        validateName()
        guard nameError == nil else { return }

        let trimmed = NameValidator.normalize(name)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = project.name
        let originalDescription = project.projectDescription
        let originalUpdatedAt = project.updatedAt
        project.name = trimmed
        project.projectDescription = desc.isEmpty ? nil : desc
        project.updatedAt = .now
        do {
            try modelContext.save()
            try VaultRepository.shared.captureFromSwiftData(context: modelContext)
            dismiss()
        } catch {
            project.name = originalName
            project.projectDescription = originalDescription
            project.updatedAt = originalUpdatedAt
            modelContext.rollback()
            saveError = "Failed to save project: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
