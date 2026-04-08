import SwiftUI
import AppKit

enum AppTheme {
    static let accent = Color.accentColor
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surfacePrimary = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.15, alpha: 1.0)
            : NSColor(white: 0.97, alpha: 1.0)
    })

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let border = Color(nsColor: .separatorColor)
    static let borderSubtle = Color(nsColor: .quaternaryLabelColor)

    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    enum Fonts {
        static let title = Font.system(size: 16, weight: .semibold)
        static let sectionHeader = Font.system(size: 13, weight: .medium)
        static let body = Font.system(size: 13)
        static let key = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let value = Font.system(size: 12, design: .monospaced)
        static let valueMasked = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let button = Font.system(size: 13, weight: .medium)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24

        static let popoverPadding: CGFloat = 12
        static let listItemPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 16
        static let cornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 16
    }

    enum Sizing {
        static let popoverWidth: CGFloat = 320
        static let popoverMaxHeight: CGFloat = 480
        static let menuBarIconSize: CGFloat = 18

        static let windowDefaultWidth: CGFloat = 800
        static let windowDefaultHeight: CGFloat = 500
        static let windowMinWidth: CGFloat = 600
        static let windowMinHeight: CGFloat = 400
        static let sidebarWidth: CGFloat = 220
        static let sidebarMinWidth: CGFloat = 180
    }
}
