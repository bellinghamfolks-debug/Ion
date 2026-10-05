import SwiftUI
import UIKit

/// Colours: deep espresso and copper in dark mode, warm cream in light mode.
/// Every text/background pair meets WCAG AA (4.5:1) and adapts to
/// "Increase Contrast".
enum Theme {
    static let background = dynamic(light: 0xF6F1EA, dark: 0x110E0C, lightHC: 0xFFFFFF, darkHC: 0x000000)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1D1916, lightHC: 0xFFFFFF, darkHC: 0x15110F)
    static let surfaceRaised = dynamic(light: 0xEFE6DB, dark: 0x2A241F, lightHC: 0xE8DCCD, darkHC: 0x2E2722)
    static let textPrimary = dynamic(light: 0x24180F, dark: 0xF5EDE3, lightHC: 0x000000, darkHC: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x5E4B3C, dark: 0xC9B8A6, lightHC: 0x3A2A1D, darkHC: 0xE6D8C8)
    static let accent = dynamic(light: 0x8C4F24, dark: 0xD9955F, lightHC: 0x6B3A16, darkHC: 0xF0B07A)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A0F07, lightHC: 0xFFFFFF, darkHC: 0x000000)
    static let separator = dynamic(light: 0xD9CCBD, dark: 0x3A322B, lightHC: 0x8A7766, darkHC: 0x8F7E6E)
    static let success = dynamic(light: 0x2F6B3A, dark: 0x7FCB8C, lightHC: 0x1F5229, darkHC: 0x9BE3A7)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xF2C14E, lightHC: 0x6A4500, darkHC: 0xFFD875)
    static let danger = dynamic(light: 0xA3261B, dark: 0xFF8A7A, lightHC: 0x7E1A11, darkHC: 0xFFA99C)

    // Drink illustration palette (decorative only).
    static let espresso = Color(hex: 0x3B1F10)
    static let coffeeBrew = Color(hex: 0x5A3118)
    static let crema = Color(hex: 0xC48A4E)
    static let milk = Color(hex: 0xF4EADC)
    static let foam = Color(hex: 0xFFFBF4)
    static let water = Color(hex: 0xBFD9E6)
    static let tea = Color(hex: 0xB86A2A)
    static let ice = Color(hex: 0xE3F2F8)

    static let profileColors: [Color] = [
        Color(hex: 0xC97B43), Color(hex: 0x4F8A8B), Color(hex: 0x9B5DA8), Color(hex: 0x5C7FC4),
    ]

    static let cornerRadius: CGFloat = 20

    private static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32) -> Color {
        Color(UIColor { traits in
            let high = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle == .dark, high) {
            case (true, true): return UIColor(hex: darkHC)
            case (true, false): return UIColor(hex: dark)
            case (false, true): return UIColor(hex: lightHC)
            case (false, false): return UIColor(hex: light)
            }
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A rounded card surface used across the app.
struct CardBackground: ViewModifier {
    var raised = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(raised ? Theme.surfaceRaised : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            )
    }
}

extension View {
    func card(raised: Bool = false) -> some View { modifier(CardBackground(raised: raised)) }

    /// Screen background that extends under the bars.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// Primary call-to-action: full width, at least 56 pt tall, copper fill.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .foregroundStyle(Theme.onAccent)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(role == .destructive ? Theme.danger : Theme.accent)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            )
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 14)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
            .contentShape(Rectangle())
    }
}
