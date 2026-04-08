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

    private static let fileNameRegex = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$|^\.[a-zA-Z0-9][a-zA-Z0-9._-]*$/

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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nameError = nil
            return
        }
        if trimmed.wholeMatch(of: Self.fileNameRegex) == nil {
            nameError = "Invalid file name format."
            return
        }
        let siblings = file.project?.files ?? []
        if siblings.contains(where: { $0.id != file.id && $0.name == trimmed }) {
            nameError = "A file with this name already exists."
            return
        }
        nameError = nil
    }

    private func saveFile() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = file.name
        let originalUpdatedAt = file.updatedAt
        let originalProjectUpdatedAt = file.project?.updatedAt
        file.name = trimmed
        file.updatedAt = .now
        file.project?.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            file.name = originalName
            file.updatedAt = originalUpdatedAt
            if let originalProjectUpdatedAt {
                file.project?.updatedAt = originalProjectUpdatedAt
            }
            saveError = "Failed to save file: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
