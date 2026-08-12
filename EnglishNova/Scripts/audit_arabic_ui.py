#!/usr/bin/env python3
"""Fail CI on high-confidence Arabic UI regressions.

This audit is intentionally conservative about grammar, but strict about copy
patterns and product labels that EnglishNova has explicitly retired. It scans
Swift string literals so old translated jargon cannot silently return later.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "EnglishNova"

# Compatibility aliases intentionally contain old strings so saved/remote
# content can be migrated safely. They are not user-facing source copy.
EXCLUDED = {
    SOURCE / "Core" / "Localization" / "L.swift",
    SOURCE / "Data" / "Local" / "CurriculumEnhancer.swift",
}

PATTERNS = [
    (re.compile(r"\bقم\s+(?:ب|بال|بإ)"), "machine-style imperative; use a direct verb"),
    (re.compile(r"\bجاري\b"), "use «جارٍ» in running-status copy"),
    (re.compile(r"(?:إضغط|إختار|إستمع|إستخدم|إكتب)"), "incorrect imperative spelling"),
    (re.compile(r"\*\*"), "raw Markdown marker in a UI string"),
]

RETIRED_LABELS = {
    "ذكاء الخادم",
    "مختبرات",
    "مختبرات المستوى المتقدم",
    "مختبر النطق",
    "مختبر الاستماع",
    "مصنع الجمل",
    "استوديو المحادثة",
    "المدرب الصوتي الجديد",
    "محادثة صوتية ذكية",
    "المراجعة الذكية",
    "خطتي الذكية",
    "خطتك الذكية",
    "مدربك الشخصي",
    "مدرب الكتابة الذكي",
    "مدرب الكتابة",
    "مصحّح الكتابة",
    "مولّد التمارين",
    "تدريب ذكي",
    "التدريب الذكي",
    "قاموسي الشخصي",
    "لوحة الصدارة",
    "التحليلات",
}

STRING = re.compile(r'"((?:\\.|[^"\\])*)"')


def swift_files():
    for path in SOURCE.rglob("*.swift"):
        if path in EXCLUDED:
            continue
        yield path


def main() -> int:
    failures: list[str] = []
    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            literals = [m.group(1) for m in STRING.finditer(line)]
            if not literals:
                continue
            for literal in literals:
                if not re.search(r"[\u0600-\u06FF]", literal):
                    continue
                for pattern, reason in PATTERNS:
                    if pattern.search(literal):
                        failures.append(
                            f"{path.relative_to(ROOT)}:{number}: {reason}: {literal}"
                        )
                if literal.strip() in RETIRED_LABELS:
                    failures.append(
                        f"{path.relative_to(ROOT)}:{number}: retired product label: {literal}"
                    )

    legal = SOURCE / "Features" / "Settings" / "LegalViews.swift"
    if not legal.exists():
        failures.append("Features/Settings/LegalViews.swift: missing dedicated legal views")
    else:
        legal_text = legal.read_text(encoding="utf-8")
        for symbol in (
            "struct PrivacyView",
            "struct TermsOfUseView",
            "struct AccessibilityStatementView",
        ):
            if symbol not in legal_text:
                failures.append(f"LegalViews.swift: missing {symbol}")

    if failures:
        print("Arabic UI copy audit failed:\n")
        for item in failures:
            print(f"- {item}")
        return 1

    print("Arabic UI copy audit: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
