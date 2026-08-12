import SwiftUI

/// Calm, high-contrast content card. The title is exposed as a VoiceOver header
/// and the icon is decorative so it never adds noise to the reading order.
struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = AppTheme.brand
    private let content: Content

    init(title: String, systemImage: String, tint: Color = AppTheme.brand,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(L(title))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.cardSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .contain)
    }
}
