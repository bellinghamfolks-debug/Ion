import SwiftUI
import UIKit

/// Basir 3.1 colour system. Every colour adapts to light and dark appearance
/// and to Increase Contrast (system setting or the in-app high-contrast
/// option, which is applied as a trait override on iOS 17 and later).
enum BasirPalette {
    static let cyan = dynamic(light: rgb(0.00, 0.44, 0.58), dark: rgb(0.36, 0.86, 1.00),
                              lightHigh: rgb(0.00, 0.30, 0.42), darkHigh: rgb(0.62, 0.95, 1.00))
    static let accent = cyan
    static let cyanDeep = dynamic(light: rgb(0.00, 0.33, 0.45), dark: rgb(0.00, 0.36, 0.48),
                                  lightHigh: rgb(0.00, 0.22, 0.32), darkHigh: rgb(0.00, 0.45, 0.58))
    static let indigo = dynamic(light: rgb(0.22, 0.27, 0.62), dark: rgb(0.48, 0.55, 1.00),
                                lightHigh: rgb(0.14, 0.18, 0.48), darkHigh: rgb(0.70, 0.75, 1.00))
    static let violet = dynamic(light: rgb(0.42, 0.30, 0.70), dark: rgb(0.62, 0.52, 0.95),
                                lightHigh: rgb(0.30, 0.18, 0.55), darkHigh: rgb(0.80, 0.72, 1.00))

    static let primaryText = dynamic(light: rgb(0.06, 0.08, 0.11), dark: .white,
                                     lightHigh: .black, darkHigh: .white)
    static let secondaryText = dynamic(light: rgb(0.25, 0.29, 0.34), dark: UIColor(white: 1, alpha: 0.78),
                                       lightHigh: rgb(0.10, 0.12, 0.15), darkHigh: UIColor(white: 1, alpha: 0.94))
    static let tertiaryText = dynamic(light: rgb(0.36, 0.40, 0.45), dark: UIColor(white: 1, alpha: 0.62),
                                      lightHigh: rgb(0.18, 0.20, 0.24), darkHigh: UIColor(white: 1, alpha: 0.86))
    /// Text and icons placed on a filled accent surface.
    static let onAccent = dynamic(light: .white, dark: rgb(0.00, 0.10, 0.14),
                                  lightHigh: .white, darkHigh: .black)

    static let background = dynamic(light: rgb(0.955, 0.965, 0.975), dark: rgb(0.020, 0.035, 0.060),
                                    lightHigh: .white, darkHigh: .black)
    static let surface = dynamic(light: .white, dark: rgb(0.075, 0.085, 0.105),
                                 lightHigh: .white, darkHigh: rgb(0.04, 0.04, 0.05))
    static let subtleFill = dynamic(light: UIColor(white: 0, alpha: 0.045), dark: UIColor(white: 1, alpha: 0.075),
                                    lightHigh: UIColor(white: 0, alpha: 0.08), darkHigh: UIColor(white: 1, alpha: 0.14))
    static let stroke = dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12),
                                lightHigh: UIColor(white: 0, alpha: 0.75), darkHigh: UIColor(white: 1, alpha: 0.80))

    static let success = dynamic(light: rgb(0.00, 0.48, 0.24), dark: rgb(0.36, 0.86, 0.55),
                                 lightHigh: rgb(0.00, 0.36, 0.16), darkHigh: rgb(0.55, 1.00, 0.70))
    static let warning = dynamic(light: rgb(0.66, 0.34, 0.00), dark: rgb(1.00, 0.70, 0.30),
                                 lightHigh: rgb(0.50, 0.24, 0.00), darkHigh: rgb(1.00, 0.82, 0.50))
    static let danger = dynamic(light: rgb(0.72, 0.10, 0.12), dark: rgb(1.00, 0.52, 0.52),
                                lightHigh: rgb(0.55, 0.00, 0.04), darkHigh: rgb(1.00, 0.72, 0.72))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor, lightHigh: UIColor, darkHigh: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark { return high ? darkHigh : dark }
            return high ? lightHigh : light
        })
    }
}

/// Consistent spacing scale used by every screen.
enum BasirSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let cardRadius: CGFloat = 22
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .system: return l10n.t("حسب النظام", "Match system")
        case .light: return l10n.t("فاتح", "Light")
        case .dark: return l10n.t("داكن", "Dark")
        }
    }
}

/// Applies the appearance and the in-app high-contrast option to every
/// window, so sheets, alerts, and system controls follow them too.
@MainActor
enum BasirTheme {
    static var supportsInAppHighContrast: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    static func apply(appearance: AppAppearance, highContrast: Bool) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
            }
            if #available(iOS 17.0, *) {
                if highContrast {
                    scene.traitOverrides.accessibilityContrast = .high
                } else if scene.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                    scene.traitOverrides.remove(UITraitAccessibilityContrast.self)
                }
            }
        }
    }
}

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BasirPalette.background
                if !reduceTransparency && contrast != .increased {
                    Circle()
                        .fill(BasirPalette.cyan.opacity(colorScheme == .dark ? 0.10 : 0.08))
                        .frame(width: geometry.size.width * 0.80)
                        .blur(radius: 80)
                        .offset(x: -geometry.size.width * 0.38, y: -geometry.size.height * 0.30)
                    Circle()
                        .fill(BasirPalette.violet.opacity(colorScheme == .dark ? 0.08 : 0.05))
                        .frame(width: geometry.size.width * 0.90)
                        .blur(radius: 96)
                        .offset(x: geometry.size.width * 0.46, y: geometry.size.height * 0.18)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let padding: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        let high = contrast == .increased
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BasirPalette.surface)
            }
            .overlay(alignment: .leading) {
                if !high {
                    // A thin accent edge on the leading side gives each card
                    // its identity without colouring the area behind text.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent.opacity(0.85))
                        .frame(width: 3)
                        .padding(.vertical, cornerRadius * 0.7)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BasirPalette.stroke, lineWidth: high ? 2 : 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark || high ? 0 : 0.06), radius: 12, y: 4)
    }
}

struct NetworkStatusPill: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: icon)
            } else {
                Label(label, systemImage: icon)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .overlay { Capsule().stroke(color.opacity(0.45), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        guard network.snapshot.isConnected else { return l10n.t("غير متصل", "Offline") }
        if settings.wifiOnly, !network.snapshot.usesWiFi { return l10n.t("بانتظار Wi‑Fi", "Waiting for Wi-Fi") }
        return l10n.t("متصل", "Online")
    }

    private var icon: String {
        network.snapshot.isConnected ? (network.snapshot.usesWiFi ? "wifi" : "antenna.radiowaves.left.and.right") : "wifi.slash"
    }

    private var color: Color { network.snapshot.isConnected ? BasirPalette.success : BasirPalette.warning }

    private var accessibilityText: String {
        var value = label
        if network.snapshot.isExpensive { value += l10n.t("، اتصال عبر بيانات الهاتف", ", using cellular data") }
        if network.snapshot.isConstrained { value += l10n.t("، وضع البيانات المنخفضة", ", Low Data Mode") }
        return value
    }
}

struct BasirHeroCard: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: BasirSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(BasirPalette.onAccent)
                .frame(width: 54, height: 54)
                .background(BasirPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(BasirPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(BasirPalette.secondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BasirSpacing.s)
    }
}

private struct AppScreenContent: ViewModifier {
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BasirSpacing.l)
            .padding(.top, BasirSpacing.xs)
            .padding(.bottom, bottomPadding)
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = BasirSpacing.cardRadius,
        padding: CGFloat = BasirSpacing.l,
        accent: Color = BasirPalette.cyan
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, padding: padding, accent: accent))
    }

    func appScreenContent(bottomPadding: CGFloat = BasirSpacing.xl) -> some View {
        modifier(AppScreenContent(bottomPadding: bottomPadding))
    }

    /// Lets VoiceOver users dismiss a sheet with the two-finger Z (escape) gesture.
    func escapeToDismiss(_ dismiss: @escaping () -> Void) -> some View {
        accessibilityAction(.escape, dismiss)
    }
}

struct ScreenHeader: View {
    let section: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(section)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BasirPalette.accent)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(BasirPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InfoCard: View {
    let title: String
    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(BasirPalette.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BasirPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }
}

struct GlassToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BasirPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(BasirPalette.cyan)
        .glassSurface()
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(BasirPalette.onAccent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BasirPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BasirPalette.stroke, lineWidth: 1)
        }
        .accessibilityAddTraits(.isButton)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BasirPalette.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BasirPalette.stroke, lineWidth: 1)
        }
    }
}

/// A compact bordered action used inside result and job cards.
struct CardActionButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? BasirPalette.onAccent : BasirPalette.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(prominent ? BasirPalette.accent : BasirPalette.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(prominent ? Color.clear : BasirPalette.accent.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Lays children out horizontally, switching to a vertical stack at
/// accessibility text sizes so labels never truncate.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = BasirSpacing.s
    @ViewBuilder let content: () -> Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}

struct SelectedFileCard: View {
    let title: String
    let filename: String
    let changeTitle: String
    let changeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "doc.badge.checkmark")
                .font(.headline)
                .foregroundStyle(BasirPalette.cyan)
            Text(filename)
                .font(.body.weight(.semibold))
                .foregroundStyle(BasirPalette.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryActionButton(title: changeTitle,
                                  systemImage: "arrow.triangle.2.circlepath",
                                  action: changeAction)
        }
        .glassSurface(accent: BasirPalette.success)
        .accessibilityElement(children: .contain)
    }
}

struct InlineMessage: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isError ? BasirPalette.danger : BasirPalette.cyan)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 18, padding: 14,
                          accent: isError ? BasirPalette.danger : BasirPalette.cyan)
            .accessibilityLabel(text)
    }
}

/// A full-width alternative to segmented controls. It remains readable at
/// large accessibility text sizes and exposes a clear selected state.
struct AccessibleSelectionRow: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    let selectedValue: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? BasirPalette.cyan : BasirPalette.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(BasirPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? BasirPalette.cyan.opacity(0.12) : BasirPalette.subtleFill,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? BasirPalette.cyan.opacity(0.75) : BasirPalette.stroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? selectedValue : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GlassSectionTitle: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(BasirPalette.cyan)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(BasirPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Section heading placed above a group of cards (not inside one).
struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(BasirPalette.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, BasirSpacing.s)
            .accessibilityAddTraits(.isHeader)
    }
}
