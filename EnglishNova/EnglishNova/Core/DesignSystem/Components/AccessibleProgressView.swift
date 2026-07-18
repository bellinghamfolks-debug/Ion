import SwiftUI

struct AccessibleProgressView: View {
    let title: String
    let value: Double
    var tint: [Color] = [AppTheme.brand, AppTheme.accentTeal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(title)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(clamped, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint.first ?? AppTheme.brand)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(AppTheme.gradient(tint))
                        .frame(width: max(6, geo.size.width * clamped))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: clamped)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(title))
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private var clamped: Double { min(1, max(0, value)) }
}
