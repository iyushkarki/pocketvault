import SwiftUI

struct SyncStatusIndicator: View {
    @Environment(SyncService.self) private var syncService

    private var icon: String {
        switch syncService.status {
        case .disabled:
            return "internaldrive.fill"
        case .synced:
            return "checkmark.icloud.fill"
        case .unavailable:
            return "exclamationmark.icloud.fill"
        case .migrating:
            return "arrow.triangle.2.circlepath.icloud.fill"
        case .error:
            return "xmark.icloud.fill"
        }
    }

    private var color: Color {
        switch syncService.status {
        case .disabled:
            return AppTheme.textTertiary
        case .synced:
            return AppTheme.success
        case .unavailable:
            return AppTheme.warning
        case .migrating:
            return AppTheme.textSecondary
        case .error:
            return AppTheme.error
        }
    }

    private var tooltip: String {
        switch syncService.status {
        case .disabled:
            return "Local only"
        case .synced:
            return "Synced via iCloud"
        case .unavailable(let reason):
            return reason
        case .migrating:
            return "Syncing..."
        case .error(let message):
            return message
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .help(tooltip)
    }
}
