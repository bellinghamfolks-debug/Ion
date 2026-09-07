#!/usr/bin/env python3
"""Verify current EnglishNova source and built-app release integrity.

The file name is retained so existing CI integrations keep working. Unlike the
old build-50 recovery guard, this validator reads the current release contract
from PROJECT_MANIFEST.json and verifies that built resources are byte-for-byte
identical to the reviewed source resources.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "PROJECT_MANIFEST.json").read_text(encoding="utf-8"))
EXPECTED_VERSION = str(MANIFEST["version"])
EXPECTED_BUILD = str(MANIFEST["build"])
EXPECTED_BUNDLE_ID = str(MANIFEST["recoveryFingerprint"]["bundleIdentifier"])
EXPECTED_FILES = {
    Path("EnglishNova/Resources/Curriculum/curriculum.json"):
        str(MANIFEST["recoveryFingerprint"]["curriculumSHA256"]),
    Path("EnglishNova/Resources/LocalizationData/translations.json"):
        str(MANIFEST["recoveryFingerprint"]["translationsSHA256"]),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"release integrity mismatch: {message}")


def verify_source() -> None:
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    build = re.search(r"(?m)^\s*CURRENT_PROJECT_VERSION:\s*([^\s#]+)", project)
    version = re.search(r"(?m)^\s*MARKETING_VERSION:\s*([^\s#]+)", project)
    require(bool(build), "CURRENT_PROJECT_VERSION is missing from project.yml")
    require(bool(version), "MARKETING_VERSION is missing from project.yml")
    require(build.group(1).strip("\"'") == EXPECTED_BUILD,
            f"source build is {build.group(1)}, manifest requires {EXPECTED_BUILD}")
    require(version.group(1).strip("\"'") == EXPECTED_VERSION,
            f"source version is {version.group(1)}, manifest requires {EXPECTED_VERSION}")

    for relative, expected in EXPECTED_FILES.items():
        path = ROOT / relative
        require(path.is_file(), f"missing source resource: {relative}")
        actual = sha256(path)
        require(actual == expected,
                f"{relative} SHA-256 is {actual}, manifest requires {expected}")


def verify_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle does not exist: {app}")
    info_path = app / "Info.plist"
    require(info_path.is_file(), f"missing {info_path}")
    with info_path.open("rb") as file:
        info = plistlib.load(file)

    require(str(info.get("CFBundleIdentifier", "")) == EXPECTED_BUNDLE_ID,
            f"bundle id is {info.get('CFBundleIdentifier')}, expected {EXPECTED_BUNDLE_ID}")
    require(str(info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
            f"bundle version is {info.get('CFBundleShortVersionString')}, expected {EXPECTED_VERSION}")
    require(str(info.get("CFBundleVersion", "")) == EXPECTED_BUILD,
            f"bundle build is {info.get('CFBundleVersion')}, expected {EXPECTED_BUILD}")

    bundle_files = {
        Path("Curriculum/curriculum.json"): EXPECTED_FILES[
            Path("EnglishNova/Resources/Curriculum/curriculum.json")
        ],
        Path("LocalizationData/translations.json"): EXPECTED_FILES[
            Path("EnglishNova/Resources/LocalizationData/translations.json")
        ],
    }
    for relative, expected in bundle_files.items():
        path = app / relative
        require(path.is_file(), f"missing app resource: {relative}")
        require(sha256(path) == expected, f"built resource differs from reviewed source: {relative}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="also verify a built .app bundle")
    args = parser.parse_args()
    verify_source()
    if args.app:
        verify_app(args.app)
    print(f"EnglishNova release integrity OK: {EXPECTED_VERSION} build {EXPECTED_BUILD}")


if __name__ == "__main__":
    main()
