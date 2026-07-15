import SwiftUI

/// Shared visual language. Colors are semantic and adapt to light/dark via the
/// system palette so the app looks correct in both without extra work.
enum Theme {
    static let cornerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 20
}

extension TestOutcome {
    /// The tint used for this outcome across cards, icons and the report.
    var color: Color {
        switch self {
        case .pass:        return .green
        case .fail:        return .red
        case .warning:     return .orange
        case .unsupported: return .gray
        case .notRun:      return .secondary
        }
    }
}

/// A rounded, theme-aware container used by the test screens and dashboard.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// A large primary button matching Apple's modern filled style.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

/// Two buttons for the user to self-assess a hardware test (works / doesn't).
struct PassFailControls: View {
    let onPass: () -> Void
    let onFail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(role: .destructive, action: onFail) {
                Label("لا يعمل", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Button(action: onPass) {
                Label("يعمل", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .controlSize(.large)
    }
}
