import SwiftUI

// MARK: - Visual language

/// A small, semantic design system shared by every Basir screen.
/// It deliberately relies on dynamic system colors and scalable text so the
/// interface remains readable in light mode, dark mode, high contrast, and
/// accessibility Dynamic Type sizes.
enum BasirTheme {
    static let brand = Color(red: 0.05, green: 0.31, blue: 0.67)
    static let brandDeep = Color(red: 0.02, green: 0.16, blue: 0.39)
    static let brandSoft = Color(red: 0.88, green: 0.93, blue: 1.00)

    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let separator = Color.primary.opacity(0.09)

    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 22
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let minimumControlHeight: CGFloat = 54
}

enum BasirTone {
    case brand, info, success, warning, danger, neutral

    var color: Color {
        switch self {
        case .brand: return BasirTheme.brand
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        case .neutral: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .brand: return "sparkles"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        case .neutral: return "circle.fill"
        }
    }
}

// MARK: - Shared copy

enum BasirCopy {
    static var verifyImportantInformation: String {
        L10n.t(
            "راجع الأسماء والأرقام والمعلومات المهمة قبل الاعتماد على النتيجة.",
            "Check names, numbers, and other important details before relying on the result."
        )
    }

    static var privateProcessingNotice: String {
        L10n.t(
            "لن يُرسل شيء إلا بعد أن تختار إجراءً واضحًا.",
            "Nothing is sent unless you choose a clear action."
        )
    }

    static var resultReady: String {
        L10n.t("النتيجة جاهزة للمراجعة.", "Your result is ready to review.")
    }

    static var noSavedItems: String {
        L10n.t("لا توجد عناصر محفوظة حتى الآن.", "Nothing has been saved yet.")
    }
}

// MARK: - Screen containers

struct BasirScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BasirTheme.sectionSpacing) {
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, BasirTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BasirTheme.screenBackground.ignoresSafeArea())
    }
}

struct BasirHero: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let systemImage: String

    init(eyebrow: String? = nil,
         title: String,
         subtitle: String,
         systemImage: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [BasirTheme.brandDeep, BasirTheme.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 128, height: 128)
                .offset(x: 36, y: -50)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BasirPageIntro: View {
    let text: String
    var tone: BasirTone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
                .font(.title3)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous)
                .stroke(BasirTheme.separator)
        )
        .accessibilityElement(children: .combine)
    }
}

struct BasirSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Cards and status

struct BasirFeatureCard: View {
    let systemImage: String
    let title: String
    let description: String
    var tone: BasirTone = .brand
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.color)
                .frame(width: 52, height: 52)
                .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(tone.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tone.color.opacity(0.10), in: Capsule())
                    }
                }

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous)
                .stroke(BasirTheme.separator)
        )
        .contentShape(RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(.isButton)
    }
}

struct BasirStatusBanner: View {
    let text: String
    var tone: BasirTone = .info
    var title: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.icon)
                .font(.title3)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.bold())
                }
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous)
                .stroke(tone.color.opacity(0.24))
        )
        .accessibilityElement(children: .combine)
    }
}

struct BasirInfoRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(BasirTheme.brand)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BasirTheme.controlRadius).stroke(BasirTheme.separator))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct BasirResultCard<Actions: View>: View {
    let title: String
    let text: String
    let actions: Actions

    init(title: String, text: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.text = text
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(title, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                actions
            }
            Divider()
            SelectableText(text: text)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BasirTheme.cardRadius).stroke(BasirTheme.separator))
    }
}

struct BasirEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(BasirTheme.brand)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BasirTheme.cardRadius).stroke(BasirTheme.separator))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inputs and buttons

struct BasirTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var minimumHeight: CGFloat = 150
    var characterLimit: Int? = nil
    @FocusState private var focused: Bool

    private var remainingText: String? {
        guard let characterLimit else { return nil }
        return L10n.t(
            "\(text.count) من \(characterLimit) حرف",
            "\(text.count) of \(characterLimit) characters"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let remainingText {
                    Text(remainingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: minimumHeight)
                    .background(Color.clear)
                    .accessibilityLabel(title)
                    .accessibilityHint(placeholder)
                    .onChange(of: text) { _, newValue in
                        guard let characterLimit, newValue.count > characterLimit else { return }
                        text = String(newValue.prefix(characterLimit))
                    }
            }
            .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous)
                    .stroke(focused ? BasirTheme.brand : BasirTheme.separator, lineWidth: focused ? 2 : 1)
            )
        }
    }
}

struct BasirPrimaryButtonStyle: ButtonStyle {
    var tone: BasirTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: BasirTheme.minimumControlHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(tone.color.opacity(configuration.isPressed ? 0.78 : 1),
                        in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BasirSecondaryButtonStyle: ButtonStyle {
    var tone: BasirTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: BasirTheme.minimumControlHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(configuration.isPressed ? 0.16 : 0.09),
                        in: RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BasirTheme.controlRadius, style: .continuous)
                    .stroke(tone.color.opacity(0.22))
            )
    }
}

struct BasirIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(BasirTheme.brand)
            .padding(10)
            .background(BasirTheme.brand.opacity(configuration.isPressed ? 0.16 : 0.09), in: Circle())
    }
}

extension View {
    func basirCardSurface(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BasirTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BasirTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BasirTheme.cardRadius).stroke(BasirTheme.separator))
    }
}
