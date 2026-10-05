import SwiftUI
import UIKit

/// Colours: warm oat cream, espresso brown and deep ink navy in light mode;
/// roasted espresso and copper in dark mode. Every text/background pair meets
/// WCAG AA (4.5:1) and adapts to "Increase Contrast" (Scripts/check_contrast.py).
enum Theme {
    static let background = dynamic(light: 0xEEE9E3, dark: 0x14100D, lightHC: 0xFFFFFF, darkHC: 0x000000)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x221C18, lightHC: 0xFFFFFF, darkHC: 0x15110F)
    static let surfaceRaised = dynamic(light: 0xF5F1EC, dark: 0x2D2621, lightHC: 0xEFE7DD, darkHC: 0x2E2722)
    static let textPrimary = dynamic(light: 0x2B1A10, dark: 0xF5EDE3, lightHC: 0x000000, darkHC: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x5C4A3D, dark: 0xCBBBAA, lightHC: 0x3A2A1D, darkHC: 0xE6D8C8)
    static let accent = dynamic(light: 0x5B3421, dark: 0xE2A776, lightHC: 0x41220F, darkHC: 0xF3BE8E)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A0F07, lightHC: 0xFFFFFF, darkHC: 0x000000)
    static let separator = dynamic(light: 0xDCD2C6, dark: 0x3A322B, lightHC: 0x8A7766, darkHC: 0x8F7E6E)
    static let success = dynamic(light: 0x2F6B3A, dark: 0x7FCB8C, lightHC: 0x1F5229, darkHC: 0x9BE3A7)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xF2C14E, lightHC: 0x6A4500, darkHC: 0xFFD875)
    static let danger = dynamic(light: 0xA3261B, dark: 0xFF8A7A, lightHC: 0x7E1A11, darkHC: 0xFFA99C)

    /// Deep navy (light periwinkle in dark mode) for the health card, selected
    /// chips and the selected tab; `onInk` is the text on it.
    static let ink = dynamic(light: 0x15284A, dark: 0xA9C2EE, lightHC: 0x0B1A35, darkHC: 0xC4D6F5)
    static let onInk = dynamic(light: 0xFFFFFF, dark: 0x0E1A30, lightHC: 0xFFFFFF, darkHC: 0x000000)
    /// Soft sky blue behind the machine picture.
    static let sky = dynamic(light: 0xD3E3F6, dark: 0x1B2738, lightHC: 0xDDE9F8, darkHC: 0x101A28)
    /// "Hot" and "Cold" drink tags.
    static let hotTag = dynamic(light: 0xFBE3CF, dark: 0x4A2A14, lightHC: 0xFFE9D8, darkHC: 0x3A1F0C)
    static let onHotTag = dynamic(light: 0x7A3A0E, dark: 0xFFD2AE, lightHC: 0x5A2806, darkHC: 0xFFE2CB)
    static let coldTag = dynamic(light: 0xDCE9F8, dark: 0x1D3350, lightHC: 0xE4EFFB, darkHC: 0x142640)
    static let onColdTag = dynamic(light: 0x1F4471, dark: 0xC9DFFF, lightHC: 0x0F2F57, darkHC: 0xDDEAFF)

    // Health bars on the navy card (decorative; the text says the state).
    static let healthGood = Color(hex: 0x3CC48A)
    static let healthWarn = Color(hex: 0xF2C14E)
    static let healthBad = Color(hex: 0xFF7A6B)

    // Drink illustration palette (decorative only).
    static let espresso = Color(hex: 0x2E170B)
    static let coffeeBrew = Color(hex: 0x4E2A14)
    static let crema = Color(hex: 0xC48A4E)
    static let milk = Color(hex: 0xF2E6D6)
    static let foam = Color(hex: 0xFFFBF5)
    static let water = Color(hex: 0xCFE3EE)
    static let tea = Color(hex: 0xB86A2A)
    static let ice = Color(hex: 0xE8F4FA)

    // Hero backgrounds: roasted brown into night navy.
    static let heroTop = Color(hex: 0x1E140E)
    static let heroBottom = Color(hex: 0x111C33)

    static let profileColors: [Color] = [
        Color(hex: 0xC97B43), Color(hex: 0x4F8A8B), Color(hex: 0x9B5DA8), Color(hex: 0x5C7FC4),
    ]

    static let cornerRadius: CGFloat = 24

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

    /// True when the system draws the floating glass tab bar (iOS 26 SDK on
    /// iOS 26), which ignores a custom selection pill.
    private static var usesGlassTabBar: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { return true }
        #endif
        return false
    }

    /// Tab bar: white bar, the selected tab in a navy pill with a white icon.
    /// On the glass tab bar the selected icon is simply navy.
    static func configureBars() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(surface)
        appearance.shadowColor = UIColor(separator)

        let item = UITabBarItemAppearance()
        let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        item.normal.iconColor = UIColor(textSecondary)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(textSecondary), .font: font]
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(ink), .font: font]
        if usesGlassTabBar {
            item.selected.iconColor = UIColor(ink)
        } else {
            item.selected.iconColor = UIColor(onInk)
            appearance.selectionIndicatorImage = tabPill()
        }
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Navigation bars: large titles in the editorial serif.
        let title = UIFont.preferredFont(forTextStyle: .largeTitle)
        let serif = title.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 0) } ?? title
        let largeAttributes: [NSAttributedString.Key: Any] = [.font: serif, .foregroundColor: UIColor(textPrimary)]
        let titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(textPrimary)]
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = largeAttributes
        edge.titleTextAttributes = titleAttributes
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = largeAttributes
        standard.titleTextAttributes = titleAttributes
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
    }

    /// A navy capsule behind the selected tab's icon, the height of the bar
    /// so it sits over the icon and leaves the title below.
    private static func tabPill() -> UIImage {
        let size = CGSize(width: 76, height: 49)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let pill = CGRect(x: 8, y: 3, width: 60, height: 30)
            UIColor(ink).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: 15).fill()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

extension Font {
    /// Editorial serif (New York) for big statements and screen titles.
    /// Scales with Dynamic Type like any text style.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
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
