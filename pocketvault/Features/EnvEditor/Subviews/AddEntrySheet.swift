import SwiftUI
import SwiftData

struct AddEntrySheet: View {
    let file: EnvFile
    @Bindable var viewModel: EnvEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager

    @State private var key = ""
    @State private var value = ""
    @State private var keyError: String?
    @State private var showDiscardAlert = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case key, value }

    private static let keyRegex = /^[A-Za-z_][A-Za-z0-9_]*$/

    private var isValid: Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && keyError == nil
    }

    private var hasChanges: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !value.isEmpty
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Add Entry")
                .font(AppTheme.Fonts.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField("KEY_NAME", text: $key)
                    .font(AppTheme.Fonts.key)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .key)
                    .onChange(of: key) {
                        lockManager.recordActivity()
                        validateKey()
                    }

                if let keyError {
                    Text(keyError)
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.error)
                }

                SecureValueField(placeholder: "Value", value: $value)
            }

            HStack {
                Button("Cancel") {
                    if hasChanges {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addEntry() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 320)
        .interactiveDismissDisabled(hasChanges)
        .onAppear { focusedField = .key }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
    }

    private func validateKey() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keyError = nil
            return
        }
        if trimmed.wholeMatch(of: Self.keyRegex) == nil {
            keyError = "Must start with a letter or underscore, containing only letters, numbers, and underscores."
            return
        }
        if (file.entries ?? []).contains(where: { !$0.isComment && $0.key == trimmed }) {
            keyError = "A key with this name already exists."
            return
        }
        keyError = nil
    }

    private func addEntry() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.addEntry(key: trimmedKey, value: value, to: file, context: modelContext) {
            dismiss()
        }
    }
}
