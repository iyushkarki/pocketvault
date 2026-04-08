import SwiftData
import Foundation
import os

final class DataManager {
    static let shared = DataManager()

    let container: ModelContainer

    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "DataManager")
    private static let cloudKitContainerID = "iCloud.app.pocketvault"

    private init() {
        let schema = Schema([Project.self, EnvFile.self, EnvEntry.self])
        let syncEnabled = UserDefaults.standard.bool(forKey: AppConfig.UserDefaultsKey.cloudKitSyncEnabled)

        let config: ModelConfiguration
        if syncEnabled {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(Self.cloudKitContainerID)
            )
            Self.logger.info("DataManager initialized with CloudKit sync enabled")
        } else {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            Self.logger.info("DataManager initialized in local-only mode")
        }

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            Self.logger.fault("Failed to create persistent store: \(error.localizedDescription)")
            fatalError("Failed to create persistent store: \(error)")
        }
    }
}
