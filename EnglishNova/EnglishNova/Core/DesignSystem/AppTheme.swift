import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12
    static let screenPadding: CGFloat = 20
    static let minimumTapHeight: CGFloat = 52
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
