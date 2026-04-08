import Foundation
import SwiftUI
import AppKit
import Combine
import os

@Observable
final class LockManager {
    private(set) var isLocked = true
    private(set) var lastLockedAt: Date?

    @ObservationIgnored
    private var timer: Timer?
    @ObservationIgnored
    private var sleepObserver: Any?
    @ObservationIgnored
    private var screenObserver: Any?
    @ObservationIgnored
    private var screenLockObserver: Any?
    @ObservationIgnored
    private let logger = Logger(
        subsystem: AppConfig.bundleIdentifier,
        category: "LockManager"
    )

    init() {
        setupSystemObservers()
        resetTimer()
    }

    deinit {
        timer?.invalidate()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let screenObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenObserver)
        }
        if let screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockObserver)
        }
    }

    func lock() {
        isLocked = true
        lastLockedAt = Date()
        timer?.invalidate()
        timer = nil
        logger.info("Vault locked")
    }

    func unlock() {
        isLocked = false
        resetTimer()
        logger.info("Vault unlocked")
    }

    func resetTimer() {
        timer?.invalidate()
        let timeout = UserDefaults.standard.double(forKey: AppConfig.UserDefaultsKey.autoLockTimeout)
        let effectiveTimeout: TimeInterval
        if UserDefaults.standard.object(forKey: AppConfig.UserDefaultsKey.autoLockTimeout) == nil {
            effectiveTimeout = AppConfig.Defaults.autoLockTimeout
        } else {
            effectiveTimeout = timeout
        }
        guard effectiveTimeout > 0 else {
            timer = nil
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: effectiveTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logger.info("Auto-lock triggered after timeout")
                self?.lock()
            }
        }
    }

    func recordActivity() {
        guard !isLocked else { return }
        resetTimer()
    }

    private var lockOnSleepEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppConfig.UserDefaultsKey.lockOnSleep) != nil {
            return defaults.bool(forKey: AppConfig.UserDefaultsKey.lockOnSleep)
        }
        return AppConfig.Defaults.lockOnSleep
    }

    private func setupSystemObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.lockOnSleepEnabled else { return }
            self.logger.info("Locking due to system sleep")
            self.lock()
        }

        screenObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.lockOnSleepEnabled else { return }
            self.logger.info("Locking due to screen sleep")
            self.lock()
        }

        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.lockOnSleepEnabled else { return }
            self.logger.info("Locking due to screen lock")
            self.lock()
        }
    }
}
