import SwiftUI

enum BasirPalette {
    static let cyan = Color(red: 0.32, green: 0.88, blue: 1.00)
    static let cyanDeep = Color(red: 0.00, green: 0.36, blue: 0.48)
    static let indigo = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let violet = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.76)
    static let tertiaryText = Color.white.opacity(0.58)
}

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.010, green: 0.035, blue: 0.075),
                        Color(red: 0.012, green: 0.075, blue: 0.145),
                        Color(red: 0.008, green: 0.030, blue: 0.065)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceTransparency {
                    Circle()
                        .fill(BasirPalette.cyan.opacity(0.10))
                        .frame(width: geometry.size.width * 0.78)
                        .blur(radius: 72)
                        .offset(x: -geometry.size.width * 0.35,
                                y: -geometry.size.height * 0.22)

                    Circle()
                        .fill(BasirPalette.violet.opacity(0.12))
                        .frame(width: geometry.size.width * 0.92)
                        .blur(radius: 86)
                        .offset(x: geometry.size.width * 0.45,
                                y: geometry.size.height * 0.10)

                    RoundedRectangle(cornerRadius: 120, style: .continuous)
                        .fill(BasirPalette.cyanDeep.opacity(0.10))
                        .frame(width: geometry.size.width * 1.18,
                               height: geometry.size.height * 0.30)
                        .blur(radius: 72)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -geometry.size.width * 0.18,
                                y: geometry.size.height * 0.34)

                    RoundedRectangle(cornerRadius: 140, style: .continuous)
                        .fill(BasirPalette.cyan.opacity(0.055))
                        .frame(width: geometry.size.width * 1.10,
                               height: geometry.size.height * 0.20)
                        .blur(radius: 80)
                        .offset(x: geometry.size.width * 0.10,
                                y: geometry.size.height * 0.48)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let padding: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(reduceTransparency
                              ? Color(red: 0.055, green: 0.055, blue: 0.065)
                              : Color(red: 0.045, green: 0.045, blue: 0.055).opacity(0.96))
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.thinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.08), accent.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.68), Color.white.opacity(0.14),
                                     BasirPalette.violet.opacity(0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: accent.opacity(0.12), radius: 18, y: 8)
    }
}

struct NetworkStatusPill: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.38), lineWidth: 1) }
            .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        guard network.snapshot.isConnected else { return l10n.t("غير متصل", "Offline") }
        if settings.wifiOnly, !network.snapshot.usesWiFi { return l10n.t("بانتظار Wi‑Fi", "Waiting for Wi-Fi") }
        return l10n.t("متصل بالإنترنت", "Online")
    }

    private var icon: String {
        network.snapshot.isConnected ? (network.snapshot.usesWiFi ? "wifi" : "antenna.radiowaves.left.and.right") : "wifi.slash"
    }

    private var color: Color { network.snapshot.isConnected ? .green : .orange }

    private var accessibilityText: String {
        var value = label
        if network.snapshot.isExpensive { value += l10n.t("، شبكة بيانات خلوية", ", cellular data") }
        if network.snapshot.isConstrained { value += l10n.t("، وضع البيانات المنخفضة", ", Low Data Mode") }
        return value
    }
}

struct BasirHeroCard: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            Color(red: 0.055, green: 0.055, blue: 0.065),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.18), lineWidth: 1) }
    }
}

private struct AppScreenContent: ViewModifier {
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, bottomPadding)
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 18,
        accent: Color = BasirPalette.cyan
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, padding: padding, accent: accent))
    }

    func appScreenContent(bottomPadding: CGFloat = 24) -> some View {
        modifier(AppScreenContent(bottomPadding: bottomPadding))
    }
}

struct ScreenHeader: View {
    let section: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BasirPalette.secondaryText)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, BasirPalette.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BasirPalette.cyanDeep, Color(red: 0.01, green: 0.27, blue: 0.43)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(BasirPalette.cyan.opacity(0.95), lineWidth: 1.5)
                .padding(4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: BasirPalette.cyan.opacity(0.28), radius: 18, y: 5)
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
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
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
        .glassSurface(accent: .green)
        .accessibilityElement(children: .contain)
    }
}

struct InlineMessage: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isError ? Color(red: 1, green: 0.72, blue: 0.72) : BasirPalette.cyan)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 18, padding: 14,
                          accent: isError ? .red : BasirPalette.cyan)
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
        .background(selected ? BasirPalette.cyan.opacity(0.12) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(selected ? BasirPalette.cyan.opacity(0.65) : Color.white.opacity(0.10),
                        lineWidth: 1)
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
        }
        .accessibilityAddTraits(.isHeader)
    }
}
