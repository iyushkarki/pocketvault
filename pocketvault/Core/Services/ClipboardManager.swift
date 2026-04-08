import AppKit
import SwiftUI

@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var hasCopiedContent = false

    @ObservationIgnored
    private var clearTimer: Timer?
    @ObservationIgnored
    private var copiedChangeCount: Int?

    @ObservationIgnored
    @AppStorage(AppConfig.UserDefaultsKey.clipboardClearTimeout) private var clearTimeout: TimeInterval = AppConfig.Defaults.clipboardClearTimeout

    private init() {}

    func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedChangeCount = NSPasteboard.general.changeCount
        hasCopiedContent = true
        scheduleClear()
    }

    private func scheduleClear() {
        clearTimer?.invalidate()
        guard clearTimeout > 0 else { return }
        clearTimer = Timer.scheduledTimer(withTimeInterval: clearTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearIfOurs()
            }
        }
    }

    private func clearIfOurs() {
        guard let ourCount = copiedChangeCount,
              NSPasteboard.general.changeCount == ourCount else {
            hasCopiedContent = false
            return
        }
        NSPasteboard.general.clearContents()
        copiedChangeCount = nil
        hasCopiedContent = false
    }
}
