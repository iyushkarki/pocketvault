import SwiftUI
import SwiftData

struct EditEntrySheet: View {
    let entry: EnvEntry
    @Bindable var viewModel: EnvEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LockManager.self) private var lockManager

    @State private var key: String
    @State private var value: String
    @State private var keyError: String?
    @State private var loadError: String?
    @State private var showDiscardAlert = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case key, value }

    private static let keyRegex = /^[A-Za-z_][A-Za-z0-9_]*$/

    private let originalKey: String
    private let originalValue: String

    init(entry: EnvEntry, viewModel: EnvEditorViewModel) {
        self.entry = entry
        self.viewModel = viewModel
        let k = entry.key
        let v: String
        let errorMessage: String?
        do {
            v = try viewModel.requiredValue(for: entry)
            errorMessage = nil
        } catch {
            v = ""
            errorMessage = error.localizedDescription
        }
        _key = State(initialValue: k)
        _value = State(initialValue: v)
        _loadError = State(initialValue: errorMessage)
        originalKey = k
        originalValue = v
    }

    private var isValid: Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && keyError == nil
    }

    private var hasChanges: Bool {
        key != originalKey || value != originalValue
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Edit Entry")
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

                if let loadError {
                    Text(loadError)
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
                Button("Save") { saveEntry() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || loadError != nil)
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
        let siblings = entry.file?.entries ?? []
        if siblings.contains(where: { $0.id != entry.id && !$0.isComment && $0.key == trimmed }) {
            keyError = "A key with this name already exists."
            return
        }
        keyError = nil
    }

    private func saveEntry() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.updateEntry(entry, key: trimmedKey, value: value, context: modelContext) {
            dismiss()
        }
    }
}
