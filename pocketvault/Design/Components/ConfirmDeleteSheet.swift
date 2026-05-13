import SwiftUI

struct ConfirmDeleteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let itemName: String
    let message: String
    let confirmButtonTitle: String
    let onConfirm: () -> Void

    @State private var confirmationText = ""
    @FocusState private var isConfirmationFocused: Bool

    private var canConfirm: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == itemName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.error)
                Text(title)
                    .font(AppTheme.Fonts.title)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(message)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Type \"\(itemName)\" to confirm.")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                TextField(itemName, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isConfirmationFocused)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(confirmButtonTitle, role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 420)
        .onAppear { isConfirmationFocused = true }
    }
}
