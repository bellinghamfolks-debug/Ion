import SwiftUI

/// A soft white card with generous rounding and a gentle shadow. With
/// "Increase Contrast" the shadow becomes a visible border.
struct CardBackground: ViewModifier {
    var raised = false
    @Environment(\.colorSchemeContrast) var contrast

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(raised ? Theme.surfaceRaised : Theme.surface)
                    .shadow(color: .black.opacity(raised || contrast == .increased ? 0 : 0.05), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: contrast == .increased ? 1.5 : 0)
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

/// Primary call-to-action: an espresso-brown capsule, at least 56 pt tall.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .foregroundStyle(Theme.onAccent)
            .background(
                Capsule()
                    .fill(role == .destructive ? Theme.danger : Theme.accent)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            )
            .contentShape(Capsule())
    }
}

/// Secondary action: an outlined capsule.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .foregroundStyle(Theme.accent)
            .background(
                Capsule()
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .background(Capsule().fill(Theme.surface))
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
            .contentShape(Capsule())
    }
}

/// A compact filled capsule that fits its label ("Refine Bean Adapt").
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .foregroundStyle(Theme.onAccent)
            .background(Capsule().fill(Theme.accent).opacity(configuration.isPressed ? 0.8 : 1))
            .contentShape(Capsule())
    }
}

/// An underlined text link ("View all", "Edit"), 44 pt tall to tap.
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .underline()
            .foregroundStyle(Theme.textPrimary)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// "HOT" / "COLD" tag shown on drink cards and pages.
struct DrinkTag: View {
    let isCold: Bool
    var onImage = false

    var body: some View {
        Label(isCold ? L("tag.cold") : L("tag.hot"), systemImage: isCold ? "snowflake" : "heat.waves")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isCold ? Theme.onColdTag : Theme.onHotTag)
            .background(Capsule().fill(isCold ? Theme.coldTag : Theme.hotTag))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isCold ? L("tag.cold") : L("tag.hot"))
    }
}

/// A small rounded chip with an icon ("☀ Lunchtime", "In use").
struct InfoChip: View {
    let text: String
    let symbol: String
    var filled = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filled ? Theme.onAccent : Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filled ? Theme.onAccent : Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Capsule().fill(filled ? Theme.accent : Theme.surface))
        .shadow(color: .black.opacity(filled ? 0 : 0.06), radius: 6, y: 2)
    }
}

/// A ring that fills to `fraction`, with any content in the middle.
/// Decorative: the surrounding element carries the spoken value.
struct RingGauge<Center: View>: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var track: Color = Theme.separator
    var lineWidth: CGFloat = 7
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Short horizontal bars that fill left to right (health overview).
struct SegmentBar: View {
    let filled: Int
    let total: Int
    var tint: Color = Theme.healthGood
    var track: Color = Color.white.opacity(0.22)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tint : track)
                    .frame(height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A section heading in the editorial serif, with an optional trailing link.
struct SectionTitle: View {
    let text: String
    var linkTitle: String?
    var action: (() -> Void)?

    init(text: String, linkTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.linkTitle = linkTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.display(.title2, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let linkTitle, let action {
                Button(linkTitle, action: action)
                    .buttonStyle(TextLinkButtonStyle())
            }
        }
    }
}

/// The large serif title at the top of a tab, in place of the navigation bar.
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.display(.largeTitle))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A list row card: icon, title, subtitle and a chevron.
struct NavigationRowCard: View {
    let title: String
    var subtitle: String?
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}
