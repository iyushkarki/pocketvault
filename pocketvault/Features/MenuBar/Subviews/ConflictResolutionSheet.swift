import SwiftUI

struct ConflictResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let local: VaultSnapshot
    let remote: VaultSnapshot
    let onResolve: (_ useLocal: Bool) async -> Void

    @State private var isResolving = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            comparison
            Divider()
            footer
        }
        .frame(width: 540)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.warning)

            Text("Sync Conflict")
                .font(.title3.bold())

            Text("This Mac and iCloud have different versions of your vault. Choose which to keep — the other will be overwritten.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    private var comparison: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            snapshotCard(
                title: "This Mac",
                snapshot: local,
                accent: AppTheme.accent
            )
            snapshotCard(
                title: "iCloud",
                snapshot: remote,
                accent: AppTheme.success
            )
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func snapshotCard(title: String, snapshot: VaultSnapshot, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                statRow(label: "Projects", value: "\(snapshot.projectCount)")
                statRow(label: "Files", value: "\(snapshot.fileCount)")
                statRow(label: "Entries", value: "\(snapshot.entryCount)")
            }

            Divider()

            Text("Updated \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
            Text("on \(snapshot.updatedByDeviceName)")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            if !snapshot.projects.isEmpty {
                Divider()
                Text("Projects")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.textSecondary)
                ForEach(snapshot.projects.prefix(6)) { project in
                    Text("• \(project.name)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                if snapshot.projects.count > 6 {
                    Text("…and \(snapshot.projects.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Decide Later") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isResolving)

            Spacer()

            Button("Use iCloud") { resolve(useLocal: false) }
                .buttonStyle(.bordered)
                .disabled(isResolving)

            Button("Use This Mac") { resolve(useLocal: true) }
                .buttonStyle(.borderedProminent)
                .disabled(isResolving)
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func resolve(useLocal: Bool) {
        isResolving = true
        Task {
            await onResolve(useLocal)
            isResolving = false
            dismiss()
        }
    }
}
