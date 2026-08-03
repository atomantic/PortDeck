import SwiftUI
import UIKit

extension Color {
    static let portAccent = adaptive(
        light: UIColor(red: 0.00, green: 0.38, blue: 0.45, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.63, blue: 0.72, alpha: 1)
    )
    static let portViolet = Color(red: 0.43, green: 0.32, blue: 0.88)
    static let portOnline = adaptive(
        light: UIColor(red: 0.00, green: 0.38, blue: 0.20, alpha: 1),
        dark: UIColor(red: 0.14, green: 0.68, blue: 0.43, alpha: 1)
    )
    static let portWarning = adaptive(
        light: UIColor(red: 0.52, green: 0.28, blue: 0.00, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.58, blue: 0.16, alpha: 1)
    )
    static let portOffline = adaptive(
        light: UIColor(red: 0.68, green: 0.10, blue: 0.14, alpha: 1),
        dark: UIColor(red: 0.88, green: 0.30, blue: 0.33, alpha: 1)
    )
    static let portCanvas = Color(uiColor: .systemGroupedBackground)
    static let portPanel = Color(uiColor: .secondarySystemGroupedBackground)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
