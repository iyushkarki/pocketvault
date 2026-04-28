import AppKit
import Darwin
import os

enum AppRelauncher {
    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "AppRelauncher")

    static var requiresManualRestartFromDebugger: Bool {
        DebuggerDetector.isAttached
    }

    static func restart() {
        guard !requiresManualRestartFromDebugger else {
            logger.info("Debugger attached; terminating current process instead of spawning a detached relaunch")
            NSApp.terminate(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { runningApplication, error in
            guard let runningApplication, error == nil else {
                if let error {
                    logger.error("Failed to relaunch app: \(error.localizedDescription)")
                } else {
                    logger.error("Failed to relaunch app: openApplication returned no running application")
                }
                return
            }

            finishRestartWhenReady(runningApplication, remainingAttempts: 20)
        }
    }

    private static func finishRestartWhenReady(_ runningApplication: NSRunningApplication, remainingAttempts: Int) {
        if runningApplication.isFinishedLaunching {
            runningApplication.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        guard remainingAttempts > 0 else {
            logger.error("Timed out waiting for relaunched app to finish launching; terminating anyway to avoid duplicate instances")
            NSApp.terminate(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            finishRestartWhenReady(runningApplication, remainingAttempts: remainingAttempts - 1)
        }
    }
}

private enum DebuggerDetector {
    static var isAttached: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride

        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
