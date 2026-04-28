import SwiftUI

struct RemoteDeletedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let remoteUpdatedAt: Date
    let remoteUpdatedByDeviceName: String
    let localProjectCount: Int
    let onResolve: (_ keepLocal: Bool) async -> Void

    @State private var isResolving = false
    @State private var showWipeConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            details
            Divider()
            footer
        }
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
        .alert("Wipe local vault?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) { resolve(keepLocal: false) }
        } message: {
            Text("This will permanently delete all \(localProjectCount) project\(localProjectCount == 1 ? "" : "s") on this Mac. This cannot be undone.")
        }
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "icloud.slash.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.warning)

            Text("iCloud Vault Was Deleted")
                .font(.title3.bold())
        }
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Your iCloud vault was deleted on \(remoteUpdatedByDeviceName) at \(remoteUpdatedAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)

            Text("This Mac still has \(localProjectCount) project\(localProjectCount == 1 ? "" : "s") locally. Choose what to do:")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Upload to iCloud").font(.body.bold())
                        Text("Restore iCloud from this Mac's vault.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } icon: {
                    Image(systemName: "icloud.and.arrow.up").foregroundStyle(AppTheme.accent)
                }

                Label {
                    VStack(alignment: .leading) {
                        Text("Wipe This Mac").font(.body.bold())
                        Text("Delete all data on this Mac too.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } icon: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.error)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.surfacePrimary)
            )
        }
        .padding(AppTheme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            Button("Decide Later") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isResolving)

            Spacer()

            Button("Wipe This Mac") { showWipeConfirmation = true }
                .buttonStyle(.bordered)
                .disabled(isResolving)

            Button("Upload to iCloud") { resolve(keepLocal: true) }
                .buttonStyle(.borderedProminent)
                .disabled(isResolving)
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func resolve(keepLocal: Bool) {
        isResolving = true
        Task {
            await onResolve(keepLocal)
            isResolving = false
            dismiss()
        }
    }
}
