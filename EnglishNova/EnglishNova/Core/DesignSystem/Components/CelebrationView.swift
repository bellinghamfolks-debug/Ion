import SwiftUI

/// A short burst of shapes around a symbol for finished lessons and sessions.
/// With Reduce Motion on, it shows the same symbol and colours without movement.
/// The decoration is hidden from VoiceOver; callers announce the result in text.
struct CelebrationView: View {
    var systemImage: String = "star.fill"
    var tint: Color = AppTheme.success
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    private let particles: [(angle: Double, distance: CGFloat, symbol: String, color: Color)] = [
        (0, 1.0, "sparkle", AppTheme.warning),
        (45, 0.85, "circle.fill", AppTheme.accentTeal),
        (90, 1.0, "star.fill", AppTheme.brand),
        (135, 0.85, "sparkle", AppTheme.streak),
        (180, 1.0, "circle.fill", AppTheme.success),
        (225, 0.85, "star.fill", AppTheme.warning),
        (270, 1.0, "sparkle", AppTheme.brandSecondary),
        (315, 0.85, "circle.fill", AppTheme.brand)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint)
                .scaleEffect(reduceMotion || burst ? 1 : 0.6)

            ForEach(particles.indices, id: \.self) { index in
                let particle = particles[index]
                let radians = particle.angle * .pi / 180
                let reach = (reduceMotion || burst ? size * 0.72 : size * 0.3) * particle.distance
                Image(systemName: particle.symbol)
                    .font(.system(size: size * 0.11))
                    .foregroundStyle(particle.color)
                    .offset(x: cos(radians) * reach, y: sin(radians) * reach)
                    .opacity(reduceMotion ? 0.9 : (burst ? 0.9 : 0))
            }
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { burst = true }
        }
    }
}
