#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
settings_path = root / "BasirConvert" / "Views" / "SettingsView.swift"
if not settings_path.is_file():
    raise SystemExit(f"R20 missing SettingsView: {settings_path}")

server_base = os.environ.get(
    "BASIR_SERVER_URL",
    "https://basir-convert-api-1045442243599.europe-west4.run.app",
).strip().rstrip("/")
if not server_base.startswith("https://"):
    raise SystemExit("R20 requires an HTTPS BASIR_SERVER_URL")

settings = settings_path.read_text(encoding="utf-8")
if "import Foundation" not in settings:
    settings = settings.replace("import SwiftUI\n", "import SwiftUI\nimport Foundation\n", 1)

# R19 merges the old Usage Policy into the Terms and exposes Privacy separately.
# R20 moves the public presentation of those documents to canonical server URLs,
# then adds FAQ, Contact, and About as server-hosted information pages as well.
new_legal_card = f'''
    private func basirPublicURL(_ path: String) -> URL {{
        let language = l10n.isArabic ? "ar" : "en"
        return URL(string: "{server_base}\\(path)?lang=\\(language)")!
    }}

    private var legalCard: some View {{
        VStack(alignment: .leading, spacing: 12) {{
            GlassSectionTitle(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill")
            Link(destination: basirPublicURL("/legal/terms")) {{
                Label(l10n.t("الشروط والأحكام", "Terms and Conditions"), systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }}
            Link(destination: basirPublicURL("/legal/privacy")) {{
                Label(l10n.t("سياسة الخصوصية", "Privacy Policy"), systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }}
        }}
        .glassSurface()
    }}

    private var publicInfoCard: some View {{
        VStack(alignment: .leading, spacing: 12) {{
            GlassSectionTitle(title: l10n.t("المساعدة والمعلومات", "Help and information"), systemImage: "questionmark.circle.fill")
            Link(destination: basirPublicURL("/help/faq")) {{
                Label(l10n.t("الأسئلة المتكررة", "Frequently Asked Questions"), systemImage: "questionmark.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }}
            Link(destination: basirPublicURL("/contact")) {{
                Label(l10n.t("التواصل", "Contact"), systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }}
            Link(destination: basirPublicURL("/about")) {{
                Label(l10n.t("عن بصير", "About Basir"), systemImage: "info.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }}
        }}
        .glassSurface()
    }}

'''

pattern = re.compile(
    r"\n    private var legalCard: some View \{.*?\n    \}\n\n(?=    private var feedbackCard: some View \{)",
    re.DOTALL,
)
settings, count = pattern.subn("\n" + new_legal_card, settings, count=1)
if count != 1:
    raise SystemExit(f"R20 legalCard replacement expected 1 match, found {count}")

# Add the new public-info card next to the existing legal card exactly once.
if "                        publicInfoCard\n" not in settings:
    body_anchor = "                        legalCard\n"
    if body_anchor not in settings:
        raise SystemExit("R20 Settings body legalCard anchor not found")
    settings = settings.replace(body_anchor, body_anchor + "                        publicInfoCard\n", 1)

settings_path.write_text(settings, encoding="utf-8")

final = settings_path.read_text(encoding="utf-8")
required = (
    'basirPublicURL("/legal/terms")',
    'basirPublicURL("/legal/privacy")',
    'basirPublicURL("/help/faq")',
    'basirPublicURL("/contact")',
    'basirPublicURL("/about")',
    'l10n.t("الشروط والأحكام", "Terms and Conditions")',
    'l10n.t("سياسة الخصوصية", "Privacy Policy")',
    'l10n.t("الأسئلة المتكررة", "Frequently Asked Questions")',
    'l10n.t("التواصل", "Contact")',
    'l10n.t("عن بصير", "About Basir")',
)
for marker in required:
    if marker not in final:
        raise SystemExit(f"R20 public-link integration missing {marker!r}")

for stale in (
    "شروط الاستخدام الكاملة",
    "سياسة الاستخدام الكاملة",
    "Full Terms of Use",
    "Full Usage Policy",
    "InstitutionLegalDocumentView(kind:",
):
    if stale in final:
        raise SystemExit(f"R20 stale local legal UI remains: {stale!r}")

print("BASIR_CLIENT_LAYER=R20_SERVER_PUBLIC_LINKS_LEGAL_FAQ_CONTACT_ABOUT")
