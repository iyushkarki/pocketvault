import Foundation
import CloudKit
import os

@MainActor
final class CloudVaultSubscription {
    static let shared = CloudVaultSubscription()

    var onManifestChanged: (@MainActor () -> Void)?

    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "CloudVaultSubscription")
    private var isStarted = false
    private var pollingActivity: NSBackgroundActivityScheduler?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        Task {
            do {
                try await CloudVaultStore.shared.ensureManifestSubscription()
                logger.info("CloudKit manifest subscription registered")
            } catch {
                logger.error("Failed to register manifest subscription: \(error.localizedDescription)")
            }
        }

        startPollingFallback()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pollingActivity?.invalidate()
        pollingActivity = nil
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard let queryNotification = notification as? CKQueryNotification else { return }
        guard queryNotification.subscriptionID == CloudVaultStore.manifestSubscriptionID else { return }
        logger.info("Received CloudKit manifest push")
        onManifestChanged?()
    }

    private func startPollingFallback() {
        let activity = NSBackgroundActivityScheduler(identifier: "\(AppConfig.bundleIdentifier).cloudvault.poll")
        activity.repeats = true
        activity.interval = 15 * 60
        activity.tolerance = 5 * 60
        activity.qualityOfService = .utility
        activity.schedule { completion in
            Task { @MainActor [weak self] in
                if case .ready = SyncCoordinator.shared.state {
                    self?.onManifestChanged?()
                }
                completion(.finished)
            }
        }
        pollingActivity = activity
    }
}
