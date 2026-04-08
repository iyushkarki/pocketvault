import SwiftUI
import SwiftData

struct CreateFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    let project: Project
    var onFileCreated: ((EnvFile) -> Void)?

    @State private var name = ""
    @State private var nameError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name }

    private static let fileNameRegex = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$|^\.[a-zA-Z0-9][a-zA-Z0-9._-]*$/

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && nameError == nil
    }

    private var hasChanges: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Add File to \(project.name)")
                .font(AppTheme.Fonts.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("File name (e.g. .env.production)", text: $name)
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
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { createFile() }
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nameError = nil
            return
        }
        if trimmed.wholeMatch(of: Self.fileNameRegex) == nil {
            nameError = "Invalid file name format."
            return
        }
        if (project.files ?? []).contains(where: { $0.name == trimmed }) {
            nameError = "A file with this name already exists."
            return
        }
        nameError = nil
    }

    private func createFile() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = EnvFile(name: trimmed)
        file.project = project
        modelContext.insert(file)
        project.updatedAt = .now
        do {
            try modelContext.save()
            let createdFile = file
            dismiss()
            onFileCreated?(createdFile)
        } catch {
            project.updatedAt = .now
            modelContext.rollback()
            modelContext.delete(file)
            saveError = "Failed to save file: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
