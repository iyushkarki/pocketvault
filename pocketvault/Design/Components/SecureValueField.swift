import SwiftUI

struct SecureValueField: View {
    let placeholder: String
    @Binding var value: String
    @Environment(LockManager.self) private var lockManager
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $value)
                        .font(AppTheme.Fonts.value)
                        .onChange(of: value) { _, _ in
                            lockManager.recordActivity()
                        }
                } else {
                    SecureField(placeholder, text: $value)
                        .font(AppTheme.Fonts.value)
                        .onChange(of: value) { _, _ in
                            lockManager.recordActivity()
                        }
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)

            Button {
                lockManager.recordActivity()
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide value" : "Show value")
            .accessibilityLabel(isRevealed ? "Hide value" : "Show value")
        }
    }
}
