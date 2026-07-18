import SwiftUI

/// Branded launch screen shown for ~3 seconds when the app opens: an animated
/// gradient logo mark with the app name.
struct SplashView: View {
    @State private var animateMark = false
    @State private var animateText = false
    @State private var glow = false

    var body: some View {
        ZStack {
            AppTheme.splashGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 150, height: 150)
                        .scaleEffect(glow ? 1.08 : 0.92)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 76, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(animateMark ? 1 : 0.5)
                        .rotationEffect(.degrees(animateMark ? 0 : -18))
                }
                .opacity(animateMark ? 1 : 0)

                VStack(spacing: 8) {
                    Text("EnglishNova")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .environment(\.layoutDirection, .leftToRight)
                    Text(L("رحلتك إلى الإنجليزية"))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .opacity(animateText ? 1 : 0)
                .offset(y: animateText ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { animateMark = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.35)) { animateText = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("EnglishNova، رحلتك إلى الإنجليزية"))
    }
}
