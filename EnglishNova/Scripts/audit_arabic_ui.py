#!/usr/bin/env python3
"""Fail CI on high-confidence Arabic UI regressions.

This is intentionally narrow. It does not try to judge literary quality; it
catches machine-translation patterns, legacy product jargon we deliberately
retired, raw markdown in UI strings, and common spelling mistakes.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "EnglishNova"

# L.swift contains compatibility aliases for old saved/remote strings; those
# aliases must not count as visible UI copy.
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
    "مختبرات المستوى المتقدم",
    "مصنع الجمل",
    "استوديو المحادثة",
    "المراجعة الذكية",
    "خطتي الذكية",
    "مدرب الكتابة الذكي",
    "مصحّح الكتابة",
    "مولّد التمارين",
}

STRING = re.compile(r'"((?:\\.|[^"\\])*)"')


def swift_files():
    for path in SOURCE.rglob("*.swift"):
        if path in EXCLUDED:
            continue
        yield path


def main() -> int:
    failures: list[str] = []
    warnings: list[str] = []
    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            # Ignore comments without string literals.
            literals = [m.group(1) for m in STRING.finditer(line)]
            if not literals:
                continue
            for literal in literals:
                if not re.search(r"[\u0600-\u06FF]", literal):
                    continue
                for pattern, reason in PATTERNS:
                    if pattern.search(literal):
                        failures.append(f"{path.relative_to(ROOT)}:{number}: {reason}: {literal}")
                if literal.strip() in RETIRED_LABELS:
                    warnings.append(
                        f"{path.relative_to(ROOT)}:{number}: legacy label normalized at runtime: {literal}"
                    )

    legal = SOURCE / "Features" / "Settings" / "LegalViews.swift"
    if not legal.exists():
        failures.append("Features/Settings/LegalViews.swift: missing dedicated legal views")
    else:
        legal_text = legal.read_text(encoding="utf-8")
        for symbol in ("struct PrivacyView", "struct TermsOfUseView", "struct AccessibilityStatementView"):
            if symbol not in legal_text:
                failures.append(f"LegalViews.swift: missing {symbol}")

    if warnings:
        print("Arabic UI copy audit warnings:")
        for item in warnings:
            print(f"- {item}")
        print()

    if failures:
        print("Arabic UI copy audit failed:\n")
        for item in failures:
            print(f"- {item}")
        return 1

    print("Arabic UI copy audit: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
