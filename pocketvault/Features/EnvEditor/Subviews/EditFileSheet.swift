import SwiftUI
import SwiftData

struct EditFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager
    @Bindable var file: EnvFile

    @State private var name: String
    @State private var nameError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name }

    private let originalName: String

    init(file: EnvFile) {
        self.file = file
        let n = file.name
        _name = State(initialValue: n)
        originalName = n
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && nameError == nil
    }

    private var hasChanges: Bool {
        name != originalName
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Rename File")
                .font(AppTheme.Fonts.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("File name", text: $name)
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
                Button("Save") { saveFile() }
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
        nameError = NameValidator.validateFileName(name, existingFiles: file.project?.files ?? [], excluding: file.id)
    }

    private func saveFile() {
        validateName()
        guard nameError == nil else { return }

        let trimmed = NameValidator.normalize(name)
        let originalName = file.name
        let originalUpdatedAt = file.updatedAt
        let originalProjectUpdatedAt = file.project?.updatedAt
        file.name = trimmed
        file.updatedAt = .now
        file.project?.updatedAt = .now
        do {
            try modelContext.save()
            try VaultRepository.shared.captureFromSwiftData(context: modelContext)
            dismiss()
        } catch {
            file.name = originalName
            file.updatedAt = originalUpdatedAt
            if let originalProjectUpdatedAt {
                file.project?.updatedAt = originalProjectUpdatedAt
            }
            modelContext.rollback()
            saveError = "Failed to save file: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
