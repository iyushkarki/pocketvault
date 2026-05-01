import SwiftUI
import SwiftData

struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    @Query(sort: \Project.name) private var projects: [Project]

    var onFileCreated: ((EnvFile) -> Void)? = nil
    var onProjectCreated: ((Project) -> Void)? = nil
    var showsFirstFile = true

    @State private var name = ""
    @State private var description = ""
    @State private var firstFileName = ".env"
    @State private var nameError: String?
    @State private var firstFileNameError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, description, fileName }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && nameError == nil
            && (!showsFirstFile || firstFileNameError == nil)
    }

    private var hasChanges: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Create Project")
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

                if showsFirstFile {
                    Divider()
                        .padding(.vertical, AppTheme.Spacing.xs)

                    Text("First file")
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField(".env", text: $firstFileName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .fileName)
                        .onChange(of: firstFileName) { _, _ in
                            lockManager.recordActivity()
                            validateFirstFileName()
                        }

                    if let firstFileNameError {
                        Text(firstFileNameError)
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.error)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createProject() }
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
        nameError = NameValidator.validateProjectName(name, existingProjects: projects)
    }

    private func validateFirstFileName() {
        guard showsFirstFile else {
            firstFileNameError = nil
            return
        }
        firstFileNameError = NameValidator.validateOptionalFileName(firstFileName, existingFiles: [])
    }

    private func createProject() {
        validateName()
        validateFirstFileName()
        guard nameError == nil, firstFileNameError == nil else { return }

        let trimmed = NameValidator.normalize(name)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed, description: desc.isEmpty ? nil : desc)
        modelContext.insert(project)

        let fileName = showsFirstFile ? NameValidator.normalize(firstFileName) : ""
        var createdFile: EnvFile?
        if !fileName.isEmpty {
            let file = EnvFile(name: fileName)
            file.project = project
            modelContext.insert(file)
            createdFile = file
        }

        do {
            try modelContext.save()
            try VaultRepository.shared.captureFromSwiftData(context: modelContext)
            let file = createdFile
            onProjectCreated?(project)
            dismiss()
            if let file {
                onFileCreated?(file)
            }
        } catch {
            modelContext.rollback()
            saveError = "Failed to save project: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
