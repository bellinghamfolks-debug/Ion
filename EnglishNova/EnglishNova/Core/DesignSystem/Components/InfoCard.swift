import SwiftUI

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
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.gradient([tint, tint.opacity(0.7)]),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(L(title)).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.cardSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .cardShadow()
        .accessibilityElement(children: .contain)
    }
}
