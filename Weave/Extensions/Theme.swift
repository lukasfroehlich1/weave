import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 6
    static let cornerRadiusSmall: CGFloat = 4

    static let paddingH: CGFloat = 12
    static let paddingV: CGFloat = 8

    static let iconSize: CGFloat = 12
    static let iconSizeSmall: CGFloat = 9
    static let iconSizeLarge: CGFloat = 14

    static let hoverOpacity: Double = 0.06
    static let activeOpacity: Double = 0.1

    static let sidebarBackground = Color(nsColor: NSColor(red: 0.141, green: 0.141, blue: 0.141, alpha: 1))
    static let tabBarBackground = Color(nsColor: NSColor(white: 0.12, alpha: 1))

    static let tooltipBackground = NSColor(white: 0.18, alpha: 0.95)
    static let tooltipCornerRadius: CGFloat = 7
    static let tooltipBorder = NSColor.white.withAlphaComponent(0.08)

    static let fontSize: CGFloat = 13
    static let fontSizeSmall: CGFloat = 11

    static let dividerOpacity: Double = 0.08

    static let pillOpacity: Double = 0.1
    static let pillHoverOpacity: Double = 0.2
    static let pillForegroundOpacity: Double = 0.8

    static func prColor(for state: PRState) -> Color {
        switch state {
        case .draft: .gray
        case .open: .green
        case .merged: .purple
        case .closed: .red
        }
    }
}
