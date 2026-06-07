// AppStatusView.swift
// Mirrors Android showStatusScreen(): a plain, screen-reader-friendly
// summary of version, connection mode, and Gemini configuration.

import SwiftUI

struct AppStatusView: View {
    @EnvironmentObject private var settings: BasirSettings

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    private var connectionMode: String {
        // The current iOS release uses a direct connection to Gemini.
        L10n.t("اتصال مباشر بـ Gemini", "Direct connection to Gemini")
    }

    private var keyState: String {
        settings.isConfigured
            ? L10n.t("مُعد", "Configured")
            : L10n.t("غير مُعد", "Not configured")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t(
                    "ملخص حالة التطبيق وإعداده على هذا الجهاز.",
                    "A summary of the app's status and configuration on this device."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                statusRow(L10n.t("التطبيق", "App"), "بصير — Basir")
                statusRow(L10n.t("الإصدار", "Version"), version)
                statusRow(L10n.t("نمط الاتصال", "Connection mode"), connectionMode)
                statusRow(L10n.t("مفتاح Gemini", "Gemini key"), keyState)
                statusRow(L10n.t("اللغة", "Language"),
                          settings.language == .arabic ? "العربية" : "English")
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("حالة التطبيق", "App status"))
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
