import Foundation

extension Notification.Name {
    static let pocketVaultRemoteVaultDeleted = Notification.Name("app.pocketvault.remoteVaultDeleted")
    static let pocketVaultNewProject = Notification.Name("app.pocketvault.newProject")
    static let pocketVaultNewFile = Notification.Name("app.pocketvault.newFile")
    static let pocketVaultRenameFile = Notification.Name("app.pocketvault.renameFile")
    static let pocketVaultDeleteFile = Notification.Name("app.pocketvault.deleteFile")
    static let pocketVaultImportEnvFile = Notification.Name("app.pocketvault.importEnvFile")
    static let pocketVaultLock = Notification.Name("app.pocketvault.lock")
}
