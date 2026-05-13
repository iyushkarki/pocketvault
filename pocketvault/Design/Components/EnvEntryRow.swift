import SwiftUI

struct EnvEntryRow: View {
    let entry: EnvEntry
    let revealedValue: String?
    let onRevealToggle: () -> Void
    let onCopy: () -> Void
    var onCopyKey: (() -> Void)?
    var onEdit: (() -> Void)?

    @State private var isHovered = false
    @State private var copied = false
    @State private var copiedKey = false
    @State private var copiedValue = false

    private var isRevealed: Bool { revealedValue != nil }
    private var maskedValue: String { "••••••••" }

    var body: some View {
        if entry.isComment {
            commentRow
        } else {
            entryRow
        }
    }

    private var commentRow: some View {
        Text("# \(entry.commentText)")
            .font(AppTheme.Fonts.caption)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppTheme.Spacing.xs)
            .padding(.horizontal, AppTheme.Spacing.sm)
    }

    private var entryRow: some View {
        HStack(spacing: 0) {
            keyLabel
                .frame(width: 180, alignment: .leading)

            valueLabel

            Spacer(minLength: AppTheme.Spacing.sm)

            actionButtons
                .opacity(isHovered || isRevealed ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? AppTheme.surfaceElevated : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.key), \(isRevealed ? "value revealed" : "value hidden")")
    }

    private var keyLabel: some View {
        Group {
            if copiedKey {
                Text("Copied!")
                    .font(AppTheme.Fonts.key)
                    .foregroundStyle(AppTheme.success)
                    .lineLimit(1)
            } else {
                Text(entry.key)
                    .font(AppTheme.Fonts.key)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onCopyKey else { return }
            onCopyKey()
            copiedKey = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copiedKey = false
            }
        }
        .help(onCopyKey != nil ? "Click to copy key" : "Key")
    }

    @ViewBuilder
    private var valueLabel: some View {
        if let value = revealedValue {
            Group {
                if copiedValue {
                    Text("Copied!")
                        .font(AppTheme.Fonts.value)
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)
                } else {
                    Text(value)
                        .font(AppTheme.Fonts.value)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onCopy()
                copiedValue = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copiedValue = false
                }
            }
            .help("Click to copy value")
        } else {
            Group {
                if copiedValue {
                    Text("Copied!")
                        .font(AppTheme.Fonts.value)
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)
                } else {
                    Text(maskedValue)
                        .font(AppTheme.Fonts.valueMasked)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onCopy()
                copiedValue = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copiedValue = false
                }
            }
            .help("Click to copy value")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if let onEdit {
                rowButton(icon: "pencil", help: "Edit entry") {
                    onEdit()
                }
            }

            rowButton(
                icon: isRevealed ? "eye.slash" : "eye",
                help: isRevealed ? "Hide value" : "Reveal value"
            ) {
                onRevealToggle()
            }
            .accessibilityLabel(isRevealed ? "Hide value for \(entry.key)" : "Reveal value for \(entry.key)")

            rowButton(
                icon: copied ? "checkmark" : "doc.on.doc",
                help: "Copy value",
                active: copied
            ) {
                onCopy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .accessibilityLabel(copied ? "Copied \(entry.key)" : "Copy value of \(entry.key)")
        }
    }

    private func rowButton(
        icon: String,
        help: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? AppTheme.success : AppTheme.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
