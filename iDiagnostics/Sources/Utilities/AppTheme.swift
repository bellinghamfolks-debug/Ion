import SwiftUI
import UIKit

enum AppTheme {
    static let radius: CGFloat = 18
    static let spacing: CGFloat = 16
    static let screenPadding: CGFloat = 18
}

extension TestOutcome {
    var color: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .warning: return .orange
        case .unsupported: return .gray
        case .notRun: return .secondary
        }
    }
}

struct DiagnosticCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(AppTheme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
            )
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
    }
}

struct OutcomeBadge: View {
    let outcome: TestOutcome

    var body: some View {
        Label(outcome.titleAr, systemImage: outcome.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(outcome.color)
            .accessibilityElement(children: .combine)
    }
}

struct MetricRow: View {
    let metric: DiagnosticMetric

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(metric.value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label)، \(metric.value)")
    }
}

struct ResultControls: View {
    let onPass: () -> Void
    let onWarning: () -> Void
    let onFail: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onPass) {
                Label("كل شيء يعمل", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button(action: onWarning) {
                Label("غير متأكد أو توجد ملاحظة", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button(role: .destructive, action: onFail) {
                Label("لا يعمل كما ينبغي", systemImage: "xmark.octagon.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}

struct PermissionHelpCard: View {
    let message: String

    var body: some View {
        DiagnosticCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("الإذن غير متاح", systemImage: "lock.trianglebadge.exclamationmark.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                Button("فتح إعدادات التطبيق") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct TestDisclaimer: View {
    var body: some View {
        Label(
            "هذا فحص إرشادي باستخدام واجهات iOS العامة، وليس تشخيصًا معتمدًا من Apple ولا بديلًا عن مركز صيانة.",
            systemImage: "info.circle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
