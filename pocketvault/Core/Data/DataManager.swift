import SwiftData
import Foundation
import os

final class DataManager {
    let container: ModelContainer

    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "DataManager")

    init() {
        let schema = Schema([Project.self, EnvFile.self, EnvEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            container = try ModelContainer(for: schema, configurations: config)
            Self.logger.info("DataManager initialized in-memory; vault is the source of truth")
        } catch {
            Self.logger.fault("Failed to create in-memory store: \(error.localizedDescription)")
            fatalError("Failed to create in-memory store: \(error)")
        }
    }
}
