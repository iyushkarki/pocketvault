import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "Pocket Vault" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                break
            }
        }
    }

    func hideFromDock() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible
            && !window.className.contains("StatusBar")
            && !window.className.contains("MenuBarExtra")
        }
        guard !hasVisibleWindows else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
