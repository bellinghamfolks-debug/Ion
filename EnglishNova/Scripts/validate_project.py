#!/usr/bin/env python3
"""Current release validation for the EnglishNova iOS project."""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "EnglishNova"
TESTS = ROOT / "EnglishNovaTests"
CURRICULUM = APP / "Resources" / "Curriculum" / "curriculum.json"
LOCALIZATION_DATA = APP / "Resources" / "LocalizationData"
TRANSLATIONS = LOCALIZATION_DATA / "translations.json"
EN_STRINGS = APP / "Localization" / "en.lproj" / "Localizable.strings"
AR_STRINGS = APP / "Localization" / "ar.lproj" / "Localizable.strings"
MANIFEST = ROOT / "PROJECT_MANIFEST.json"
PROJECT_YML = ROOT / "project.yml"
INFO = APP / "Info.plist"
REPO = ROOT.parent

errors: list[str] = []
notes: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def contains_arabic(value: str) -> bool:
    return bool(re.search(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]", value))


def parse_strings(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$', re.MULTILINE)
    result: dict[str, str] = {}
    for key, value in pattern.findall(text):
        key = key.replace(r'\"', '"').replace(r'\\', '\\')
        value = value.replace(r'\n', '\n').replace(r'\"', '"').replace(r'\\', '\\')
        result[key] = value
    return result


manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
project_yml = PROJECT_YML.read_text(encoding="utf-8")
info = INFO.read_text(encoding="utf-8")
app_files = sorted(APP.rglob("*.swift"))
test_files = sorted(TESTS.rglob("*.swift"))

require(manifest.get("swiftSourceFiles") == len(app_files),
        f"PROJECT_MANIFEST swiftSourceFiles={manifest.get('swiftSourceFiles')} but source has {len(app_files)}")
require(manifest.get("testFiles") == len(test_files),
        f"PROJECT_MANIFEST testFiles={manifest.get('testFiles')} but tests have {len(test_files)}")
require(len({p.relative_to(APP) for p in app_files}) == len(app_files), "Duplicate Swift source paths detected")

marketing = re.search(r"MARKETING_VERSION:\s*([^\s]+)", project_yml)
require(marketing is not None, "MARKETING_VERSION is missing from project.yml")
if marketing:
    require(manifest.get("version") == marketing.group(1),
            f"Manifest version {manifest.get('version')} does not match MARKETING_VERSION {marketing.group(1)}")

# Current curriculum integrity. Manifest equality catches accidental loss, while
# minimum floors prevent a stale manifest from blessing a major regression.
data = json.loads(CURRICULUM.read_text(encoding="utf-8"))
levels = data.get("levels", [])
lessons = [lesson for level in levels for unit in level.get("units", []) for lesson in unit.get("lessons", [])]
exercises = [exercise for lesson in lessons for exercise in lesson.get("exercises", [])]
vocabulary = [word for lesson in lessons for word in lesson.get("vocabulary", [])]
level_counts = {level.get("level", "").upper(): sum(len(unit.get("lessons", [])) for unit in level.get("units", [])) for level in levels}

require(len(levels) == manifest.get("levels") == 6, f"Unexpected CEFR level count: {len(levels)}")
require(len(lessons) == manifest.get("lessons") and len(lessons) >= 232, f"Unexpected lesson count: {len(lessons)}")
require(level_counts.get("A0") == manifest.get("a0Lessons") == 60, f"Unexpected A0 lesson count: {level_counts.get('A0')}")
require(level_counts.get("A1") == manifest.get("a1Lessons") == 60, f"Unexpected A1 lesson count: {level_counts.get('A1')}")
require(len(exercises) == manifest.get("exercises") and len(exercises) >= 5940, f"Unexpected base exercise count: {len(exercises)}")
require(len(vocabulary) == manifest.get("vocabularyEntries") and len(vocabulary) >= 1424, f"Unexpected vocabulary count: {len(vocabulary)}")
for label, ids in {
    "lessons": [x.get("id") for x in lessons],
    "exercises": [x.get("id") for x in exercises],
}.items():
    duplicates = [key for key, count in Counter(ids).items() if key and count > 1]
    require(not duplicates, f"Duplicate {label} IDs: {duplicates[:10]}")

# Arabic prompts imported from older content may include an English instruction
# prefix. Every prefix in the raw content must have an explicit runtime repair.
enhancer = (APP / "Data" / "Local" / "CurriculumEnhancer.swift").read_text(encoding="utf-8")
english_prefixes: set[str] = set()
for exercise in exercises:
    prompt = str(exercise.get("promptAr") or "").strip()
    if prompt and prompt[0].isascii() and prompt[0].isalpha() and contains_arabic(prompt) and ":" in prompt:
        english_prefixes.add(prompt.split(":", 1)[0].strip() + ":")
for prefix in sorted(english_prefixes):
    require(f'(\"{prefix}\",' in enhancer,
            f"ArabicLearningCopy has no runtime repair for English prompt prefix: {prefix}")
notes.append(f"English prompt prefixes covered by runtime enhancer: {len(english_prefixes)}")

# Literal L()/Lf() copy can resolve through the primary JSON map, supplemental
# interface maps, the standard en.lproj bundle, or the intentionally small exact map.
translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
supplemental_files = sorted(LOCALIZATION_DATA.glob("interface_en_*.json"))
require(bool(supplemental_files), "Supplemental English UI localization files are missing")
for supplemental in supplemental_files:
    payload = json.loads(supplemental.read_text(encoding="utf-8"))
    require(isinstance(payload, dict) and bool(payload), f"Invalid supplemental localization file: {supplemental.name}")
    translations.update(payload)
notes.append(f"Merged English JSON translation entries: {len(translations)} across {1 + len(supplemental_files)} files")
en_strings = parse_strings(EN_STRINGS)
ar_strings = parse_strings(AR_STRINGS)
require(len(en_strings) > 0, "English Localizable.strings could not be parsed")
require(len(ar_strings) > 0, "Arabic Localizable.strings could not be parsed")
require("EnglishNova/Localization" in project_yml, "Localized .lproj resources are not included in project.yml")

localizer_source = (APP / "Core" / "Localization" / "L.swift").read_text(encoding="utf-8")
require("bundledEnglish" in localizer_source, "Localizer does not fall back to en.lproj")
english_section = localizer_source.split("private enum EnglishInterfaceCopy", 1)[-1]
english_exact_section = english_section.split("static func dynamic", 1)[0]
english_exact_keys = set(re.findall(r'"([^"\n]*[\u0600-\u06FF][^"\n]*)"\s*:', english_exact_section))
require(bool(english_exact_keys), "EnglishInterfaceCopy exact map could not be parsed")
localization_calls = re.compile(r'\b(?:L|Lf)\(\s*\"((?:\\.|[^\"\\])*)\"')
missing_literal_keys: set[str] = set()
for path in app_files:
    text = path.read_text(encoding="utf-8")
    for match in localization_calls.finditer(text):
        key = match.group(1).replace('\\\"', '\"')
        if not contains_arabic(key):
            continue
        candidates = [translations.get(key), en_strings.get(key)]
        has_table_translation = any(value and value.strip() and value.strip() != key for value in candidates)
        if not has_table_translation and key not in english_exact_keys:
            missing_literal_keys.add(key)
require(not missing_literal_keys,
        "Missing English translations for literal UI keys: " + " | ".join(sorted(missing_literal_keys)[:100]))
notes.append(f"Bundled English string entries: {len(en_strings)}")

# Google iOS wiring. Actual IDs remain environment values, never source secrets.
for token in ("GoogleSignIn-iOS", "GoogleSignInSwift", "GoogleSignIn"):
    require(token in project_yml, f"Google dependency/configuration missing from project.yml: {token}")
for token in ("$(GOOGLE_IOS_CLIENT_ID)", "$(GOOGLE_SERVER_CLIENT_ID)", "$(GOOGLE_REVERSED_CLIENT_ID)"):
    require(token in info, f"Google build placeholder missing from Info.plist: {token}")
app_entry = (APP / "App" / "EnglishNovaApp.swift").read_text(encoding="utf-8")
account_view = (APP / "Features" / "Account" / "AccountView.swift").read_text(encoding="utf-8")
require("GIDSignIn.sharedInstance.handle(url)" in app_entry, "Google redirect handling is missing")
require("idToken" in account_view and "GIDServerClientID" in account_view, "Google ID-token server flow is incomplete")

# Production server authentication must fail closed.
server_auth = (REPO / "server" / "src" / "auth.js").read_text(encoding="utf-8")
server_index = (REPO / "server" / "src" / "index.js").read_text(encoding="utf-8")
server_config = (REPO / "server" / "src" / "config.js").read_text(encoding="utf-8")
require("dev-insecure-secret-change-me" not in server_auth, "Insecure production JWT fallback is still present")
require("assertRuntimeConfig()" in server_index, "Server does not validate runtime configuration at startup")
require("GOOGLE_SERVER_CLIENT_ID" in server_config and "JWT_SECRET" in server_config,
        "Server production auth configuration validation is incomplete")

workflow = (REPO / ".github" / "workflows" / "swift.yml").read_text(encoding="utf-8")
codemagic = (REPO / "codemagic.yaml").read_text(encoding="utf-8")
for name in ("GOOGLE_IOS_CLIENT_ID", "GOOGLE_SERVER_CLIENT_ID", "GOOGLE_REVERSED_CLIENT_ID"):
    require(name in workflow, f"GitHub Actions does not wire {name}")
    require(name in codemagic, f"Codemagic does not wire {name}")
require("validate_project.py" in workflow, "GitHub Actions is not running current project validation")
require("validate_google_config.sh" in workflow, "Unsigned IPA job is not enforcing Google OAuth configuration")
require("EnglishNova-source-latest" in workflow, "CI does not publish a source snapshot artifact")

readme = (ROOT / "README.md").read_text(encoding="utf-8")
server_readme = (REPO / "server" / "README.md").read_text(encoding="utf-8")
legal_copy = (APP / "Features" / "Settings" / "LegalViews.swift").read_text(encoding="utf-8")
require("لا توجد مكتبات خارجية" not in readme, "README still claims there are no external dependencies")
require("Sign in with Apple" not in server_readme, "Server README still documents removed Apple auth")
require("Sign in with Apple" not in legal_copy and "تسجيل الدخول باستخدام Apple" not in legal_copy,
        "Privacy copy still documents removed Apple sign-in")
require("Google ID token" in legal_copy and "رمز هوية صادرًا من Google" in legal_copy,
        "Privacy copy does not accurately document Google sign-in")

if errors:
    print("EnglishNova release validation: FAILED\n")
    for item in errors:
        print(f"- {item}")
    sys.exit(1)

print("EnglishNova release validation: PASS")
print(f"- Swift app files: {len(app_files)}")
print(f"- XCTest files: {len(test_files)}")
print(f"- Base curriculum: {len(lessons)} lessons / {len(exercises)} exercises / {len(vocabulary)} vocabulary entries")
for note in notes:
    print(f"- {note}")
print(f"- Literal localization keys checked across {len(app_files)} Swift files")
print("- Google client/server wiring and production auth fail-closed checks present")
