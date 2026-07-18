import SwiftUI

/// A tiny, app-wide "toast" system: a small confirmation banner that slides up
/// from the bottom, then auto-dismisses. Call `ToastCenter.shared.show(...)`
/// from anywhere (views or plain model code) to confirm an action — e.g. after
/// picking a photo, saving, or signing out.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    enum Style {
        case success, info, error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .success: return AppTheme.success
            case .info: return AppTheme.brand
            case .error: return AppTheme.streak
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a confirmation. Replaces any visible toast; auto-hides after ~2.2s.
    func show(_ message: String, style: Style = .success) {
        current = Toast(message: message, style: style)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        current = nil
        dismissTask?.cancel()
        dismissTask = nil
    }
}

/// The banner shown for a toast: an icon + message pill with a soft shadow,
/// tappable to dismiss early. Mirrors correctly in the app's RTL layout.
private struct ToastBanner: View {
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.tint)
                .font(.system(size: 18, weight: .semibold))
            // Toast messages arrive as plain Strings, so SwiftUI won't localize
            // them implicitly. Look the message up in Localizable.strings at
            // display time; static messages become English in English mode, and
            // interpolated ones fall back to the original text.
            Text(NSLocalizedString(toast.message, comment: "toast"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            Capsule(style: .continuous).stroke(toast.style.tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}

/// Attach at the app root so toasts float above every screen.
struct ToastOverlay: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.current {
                    ToastBanner(toast: toast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { center.dismiss() }
                        .id(toast.id)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: center.current)
    }
}

extension View {
    /// Renders app-wide toasts above this view. Apply once, at the root.
    func toastLayer() -> some View { modifier(ToastOverlay()) }
}
