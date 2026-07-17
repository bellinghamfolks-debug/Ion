import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.minimumTapHeight)
            .background(AppTheme.brandGradient,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isDisabled ? 0.5 : 1)
            .shadow(color: AppTheme.brand.opacity(isDisabled ? 0 : 0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// A button style that gently scales on press for tactile feedback.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
