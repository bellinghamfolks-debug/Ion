import SwiftUI

/// The app's design language: spacing tokens, an adaptive brand palette,
/// gradients, and shadow helpers. Colors are built from dynamic `UIColor`s so
/// they adapt automatically to light and dark mode without an asset catalog.
enum AppTheme {
    // MARK: Metrics
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14
    static let screenPadding: CGFloat = 20
    static let minimumTapHeight: CGFloat = 52
    static let cardSpacing: CGFloat = 16

    // MARK: Brand palette (adaptive light/dark)
    /// Primary brand indigo/violet — the app's accent.
    static let brand = dynamic(light: rgb(0.36, 0.31, 0.86), dark: rgb(0.53, 0.49, 0.98))
    /// Secondary violet/magenta used in gradients.
    static let brandSecondary = dynamic(light: rgb(0.60, 0.30, 0.90), dark: rgb(0.72, 0.45, 0.99))
    /// A fresh teal used for positive/progress accents.
    static let accentTeal = dynamic(light: rgb(0.11, 0.66, 0.63), dark: rgb(0.26, 0.80, 0.76))
    static let success = dynamic(light: rgb(0.16, 0.66, 0.38), dark: rgb(0.35, 0.82, 0.53))
    static let warning = dynamic(light: rgb(0.92, 0.60, 0.12), dark: rgb(0.99, 0.72, 0.29))
    static let streak  = dynamic(light: rgb(0.95, 0.44, 0.20), dark: rgb(0.99, 0.55, 0.31))

    /// Elevated card surface (slightly raised from the grouped background).
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: Gradients
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [brand, brandSecondary, accentTeal],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Deep, calm gradient used only for the launch screen. Fixed dark tones
    /// (not theme-adaptive) so it never glares in bright surroundings while the
    /// white logo stays crisp and readable.
    static var splashGradient: LinearGradient {
        LinearGradient(
            colors: [Color(uiColor: rgb(0.11, 0.09, 0.29)),
                     Color(uiColor: rgb(0.22, 0.14, 0.44)),
                     Color(uiColor: rgb(0.14, 0.11, 0.34))],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Helpers
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Soft shadow used by elevated cards.
extension View {
    func cardShadow() -> some View {
        shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

/// A subtle branded gradient wash behind screens (replaces the flat grouped
/// background) — depth while staying calm and readable in both themes.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    LinearGradient(
                        colors: [AppTheme.brand.opacity(0.10), .clear, AppTheme.accentTeal.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
