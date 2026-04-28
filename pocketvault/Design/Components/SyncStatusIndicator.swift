import SwiftUI

struct SyncStatusIndicator: View {
    @Environment(SyncCoordinator.self) private var coordinator

    private var icon: String {
        switch coordinator.state {
        case .off: return "internaldrive.fill"
        case .ready: return "checkmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
        case .conflict: return "exclamationmark.icloud.fill"
        case .remoteDeleted: return "trash.slash.circle.fill"
        case .needsAttention: return "xmark.icloud.fill"
        }
    }

    private var color: Color {
        switch coordinator.state {
        case .off: return AppTheme.textTertiary
        case .ready: return AppTheme.success
        case .syncing: return AppTheme.textSecondary
        case .conflict, .remoteDeleted: return AppTheme.warning
        case .needsAttention: return AppTheme.error
        }
    }

    private var tooltip: String {
        switch coordinator.state {
        case .off: return "Local only"
        case .ready:
            if let last = coordinator.lastSyncedAt {
                return "Synced \(Self.relativeFormatter.localizedString(for: last, relativeTo: .now))"
            }
            return "Synced via iCloud"
        case .syncing: return "Syncing..."
        case .conflict: return "Conflict needs resolution"
        case .remoteDeleted: return "iCloud vault was deleted"
        case .needsAttention(let kind):
            switch kind {
            case .iCloudKeychainUnavailable(let reason): return reason
            case .cloudKitAccountUnavailable(let message): return message
            case .remoteUnreadable: return "iCloud copy can't be read on this Mac"
            case .syncError(let message): return message
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .help(tooltip)
    }
}
