#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
settings_path = root / "BasirConvert" / "Views" / "SettingsView.swift"
legal_path = root / "BasirConvert" / "Views" / "InstitutionLegalScreens.swift"
for path in (settings_path, legal_path):
    if not path.is_file():
        raise SystemExit(f"R21 missing required source: {path}")

# This value is transport configuration, not user-visible content. A custom
# public domain can later be supplied as BASIR_PUBLIC_CONTENT_BASE_URL without
# changing Swift code. Until then it falls back to the existing API endpoint.
server_base = os.environ.get(
    "BASIR_PUBLIC_CONTENT_BASE_URL",
    os.environ.get(
        "BASIR_SERVER_URL",
        "https://basir-convert-api-1045442243599.europe-west4.run.app",
    ),
).strip().rstrip("/")
if not server_base.startswith("https://"):
    raise SystemExit("R21 requires an HTTPS public-content base URL")

native_source = f'''import SwiftUI
import Foundation

private struct BasirPublicSection: Decodable, Identifiable {{
    let id: Int
    let title: String
    let body: String
}}

private struct BasirPublicDocument: Decodable {{
    let slug: String
    let language: String
    let title: String
    let updated: String
    let intro: String
    let sections: [BasirPublicSection]
}}

struct ServerPublicDocumentView: View {{
    let slug: String
    let isArabic: Bool

    @State private var document: BasirPublicDocument?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {{
        Group {{
            if let document {{
                ScrollView {{
                    VStack(alignment: .leading, spacing: 18) {{
                        Text(document.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)

                        Text((isArabic ? "آخر تحديث: " : "Last updated: ") + document.updated)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(document.intro)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(document.sections) {{ section in
                            VStack(alignment: .leading, spacing: 7) {{
                                Text(section.title)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                Text(section.body)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }}
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain)
                        }}
                    }}
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }}
            }} else if isLoading {{
                ProgressView(isArabic ? "جاري تحميل المحتوى…" : "Loading content…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(isArabic ? "جاري تحميل المحتوى" : "Loading content")
            }} else {{
                VStack(spacing: 14) {{
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(errorMessage ?? (isArabic ? "تعذر تحميل المحتوى." : "Unable to load content."))
                        .multilineTextAlignment(.center)
                    Button(isArabic ? "إعادة المحاولة" : "Try Again") {{
                        Task {{ await load() }}
                    }}
                    .buttonStyle(.borderedProminent)
                }}
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }}
        }}
        .navigationTitle(document?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\\(slug)-\\(isArabic)") {{
            await load()
        }}
    }}

    private var fallbackTitle: String {{
        switch slug {{
        case "terms": return isArabic ? "الشروط والأحكام" : "Terms and Conditions"
        case "privacy": return isArabic ? "سياسة الخصوصية" : "Privacy Policy"
        case "faq": return isArabic ? "الأسئلة المتكررة" : "Frequently Asked Questions"
        case "contact": return isArabic ? "التواصل" : "Contact"
        case "about": return isArabic ? "عن بصير" : "About Basir"
        default: return isArabic ? "بصير" : "Basir"
        }}
    }}

    @MainActor
    private func load() async {{
        isLoading = true
        errorMessage = nil
        document = nil
        let language = isArabic ? "ar" : "en"
        guard var components = URLComponents(string: "{server_base}/api/public/content/\\(slug)") else {{
            isLoading = false
            errorMessage = isArabic ? "تعذر تجهيز عنوان المحتوى." : "Unable to prepare the content request."
            return
        }}
        components.queryItems = [URLQueryItem(name: "lang", value: language)]
        guard let url = components.url else {{
            isLoading = false
            errorMessage = isArabic ? "تعذر تجهيز عنوان المحتوى." : "Unable to prepare the content request."
            return
        }}
        do {{
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {{
                throw URLError(.badServerResponse)
            }}
            let decoded = try JSONDecoder().decode(BasirPublicDocument.self, from: data)
            guard decoded.slug == slug else {{ throw URLError(.cannotParseResponse) }}
            document = decoded
            isLoading = false
        }} catch {{
            isLoading = false
            errorMessage = isArabic
                ? "تعذر تحميل المحتوى من بصير. تحقق من الاتصال وحاول مرة أخرى."
                : "Basir could not load this content. Check your connection and try again."
        }}
    }}
}}
'''
legal_path.write_text(native_source, encoding="utf-8")

settings = settings_path.read_text(encoding="utf-8")
replacement = '''
    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill")
            NavigationLink {
                ServerPublicDocumentView(slug: "terms", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("الشروط والأحكام", "Terms and Conditions"), systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "privacy", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("سياسة الخصوصية", "Privacy Policy"), systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
        .glassSurface()
    }

    private var publicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("المساعدة والمعلومات", "Help and information"), systemImage: "questionmark.circle.fill")
            NavigationLink {
                ServerPublicDocumentView(slug: "faq", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("الأسئلة المتكررة", "Frequently Asked Questions"), systemImage: "questionmark.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "contact", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("التواصل", "Contact"), systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "about", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("عن بصير", "About Basir"), systemImage: "info.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
        .glassSurface()
    }

'''
pattern = re.compile(
    r"\n    private func basirPublicURL\(_ path: String\) -> URL \{.*?\n    private var publicInfoCard: some View \{.*?\n    \}\n\n(?=    private var feedbackCard: some View \{)",
    re.DOTALL,
)
settings, count = pattern.subn("\n" + replacement, settings, count=1)
if count != 1:
    raise SystemExit(f"R21 expected R20 public-link block once, found {count}")
settings_path.write_text(settings, encoding="utf-8")

final = settings_path.read_text(encoding="utf-8")
required = (
    'ServerPublicDocumentView(slug: "terms"',
    'ServerPublicDocumentView(slug: "privacy"',
    'ServerPublicDocumentView(slug: "faq"',
    'ServerPublicDocumentView(slug: "contact"',
    'ServerPublicDocumentView(slug: "about"',
)
for marker in required:
    if marker not in final:
        raise SystemExit(f"R21 native content integration missing {marker!r}")
for forbidden in ("basirPublicURL(", "Link(destination:", "run.app", "الكاملة"):
    if forbidden in final:
        raise SystemExit(f"R21 user-facing Settings still exposes stale external link marker {forbidden!r}")

print("BASIR_CLIENT_LAYER=R21_NATIVE_SERVER_CONTENT_NO_VISIBLE_HOST")
