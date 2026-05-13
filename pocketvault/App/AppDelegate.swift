import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for CloudKit remote notifications")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor in
            CloudVaultSubscription.shared.handleRemoteNotification(userInfo)
        }
    }

    static func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier == MainWindowCloseHandler.mainWindowIdentifier }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

    }
}
